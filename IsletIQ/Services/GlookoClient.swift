import Foundation
import SwiftData
#if canImport(WebKit)
import WebKit
#endif

/// Glooko patient-portal integration.
///
/// Glooko does not issue patient API keys, so we can't hit a documented endpoint.
/// Instead `GlookoLoginView` presents Glooko's own web login in a `WKWebView`.
/// After the user authenticates (email + password + MFA / SSO as Glooko requires),
/// they stay in the same WebView and tap "Export to CSV" on any report. The
/// WebView intercepts the resulting download — either via `WKDownloadDelegate`
/// (HTTP `Content-Disposition: attachment`) or via an injected JS bridge that
/// catches client-side Blob downloads — and hands the raw CSV bytes to this
/// client, which saves them to the app's Documents directory and parses them
/// through `GlookoImporter`.
enum GlookoClient {
    static let host = "us.my.glooko.com"
    static let loginURL = URL(string: "https://us.my.glooko.com/users/sign_in")!
    static let sessionCookieName = "_glooko_session"

    /// These flags are just UI state, not secrets — stored in UserDefaults so
    /// `@AppStorage` in SwiftUI views observes them automatically and the
    /// Settings card re-renders the moment `recordSync()` fires. Session
    /// cookies still live in `WKWebsiteDataStore`, which is where they belong.
    static let sessionFlagKey = "glooko_session_active"
    static let lastSyncKey = "glooko_last_sync"

    private static var defaults: UserDefaults { .standard }

    // MARK: - Session state

    static var isAuthenticated: Bool {
        defaults.bool(forKey: sessionFlagKey)
    }

    static var lastSync: Date? {
        let t = defaults.double(forKey: lastSyncKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func markAuthenticated() {
        defaults.set(true, forKey: sessionFlagKey)
    }

    static func recordSync() {
        defaults.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
    }

    #if canImport(WebKit)
    /// Clear the session flag and drop Glooko cookies from the shared
    /// `WKWebsiteDataStore` so the next `GlookoLoginView` starts fresh. Also
    /// wipes Glooko-origin localStorage/sessionStorage (where our ready flag
    /// lives) so reconnects start idle.
    @MainActor
    static func clearSession() async {
        defaults.removeObject(forKey: sessionFlagKey)
        defaults.removeObject(forKey: lastSyncKey)

        let store = WKWebsiteDataStore.default()
        // Cookies
        let cookies = await store.httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain.contains("glooko.com") {
            await store.httpCookieStore.deleteCookie(cookie)
        }
        // Local + session storage (ready flag lives here)
        let types: Set<String> = [
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
        ]
        let records = await store.dataRecords(ofTypes: types)
        let glooko = records.filter { $0.displayName.contains("glooko.com") }
        if !glooko.isEmpty {
            await store.removeData(ofTypes: types, for: glooko)
        }
    }
    #endif

    // MARK: - CSV persistence + inspection

    /// Save a captured CSV/zip to `Documents/Glooko/` with a timestamped
    /// filename. Does NOT stamp `lastSync` — that's reserved for the moment
    /// we actually import rows, so a failed export doesn't falsely flip the
    /// Settings card to "Connected".
    @discardableResult
    static func saveCSV(data: Data, suggestedFilename: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent("Glooko", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let cleanName = suggestedFilename.isEmpty ? "glooko.csv" : suggestedFilename
        let fileURL = dir.appendingPathComponent("\(stamp)_\(cleanName)")
        try data.write(to: fileURL)
        return fileURL
    }

    /// Best-effort guess at what kind of Glooko report a file is.
    /// Detects zip archives by magic bytes, and otherwise runs the content
    /// through each CSV parser and returns whichever matches — plus a small
    /// text sample so the user and I can see what Glooko actually sent.
    static func inspect(data: Data) -> Inspection {
        // ZIP archive (PK\x03\x04) — multiple CSVs inside. Need a real
        // unzipper to parse; for now, surface it so we know to add one.
        let header = data.prefix(4)
        if header.count >= 4, header[0] == 0x50, header[1] == 0x4B {
            return Inspection(
                kind: "ZIP archive",
                rows: 0,
                sample: "ZIP file (\(data.count) bytes). Needs an unzip step — each inner CSV parses separately."
            )
        }

        let csv = String(data: data, encoding: .utf8) ?? ""
        let sample = csv
            .components(separatedBy: .newlines)
            .prefix(3)
            .joined(separator: " ⏎ ")
            .trimmingCharacters(in: .whitespaces)
            .prefix(240)

        let cgm = GlookoImporter.parseCGM(from: csv)
        if !cgm.isEmpty { return Inspection(kind: "CGM", rows: cgm.count, sample: String(sample)) }
        let bolus = GlookoImporter.parseBolus(from: csv)
        if !bolus.isEmpty { return Inspection(kind: "Bolus", rows: bolus.count, sample: String(sample)) }
        let insulin = GlookoImporter.parseInsulinSummary(from: csv)
        if !insulin.isEmpty { return Inspection(kind: "Insulin summary", rows: insulin.count, sample: String(sample)) }
        let rawLines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        return Inspection(kind: "Unrecognized format", rows: rawLines, sample: String(sample))
    }

    struct Inspection {
        let kind: String
        let rows: Int
        let sample: String
    }

    // MARK: - Archive import

    /// Summary of what `importArchive` did.
    struct ImportResult {
        var cgmImported: Int = 0
        var bolusImported: Int = 0
        var basalImported: Int = 0
        var filesProcessed: [String] = []
        var unknownFiles: [String] = []
        /// Every filename MiniZip extracted — even ones that weren't processed
        /// or couldn't be parsed. Useful for debugging when neither
        /// `filesProcessed` nor `unknownFiles` has anything.
        var extractedFilenames: [String] = []
        /// Diagnostic preview of the first recognized file's first lines.
        var sample: String = ""
        /// Non-nil when the download looked like a zip. Lets the failure UI
        /// explain "zip had 0 entries" vs "zip parse error" vs "not a zip".
        var zipInfo: String?
        /// Earliest and latest timestamps seen across all imported CGM rows.
        /// Reveals when Glooko's dropdown selection didn't actually switch
        /// ranges (e.g. only today's data made it through even though the
        /// user picked "2 weeks").
        var earliestTimestamp: Date?
        var latestTimestamp: Date?
        /// True if we extracted at least one recognizable row.
        var didImport: Bool {
            cgmImported + bolusImported + basalImported > 0
        }
        var summary: String {
            var parts: [String] = []
            if cgmImported > 0 {
                var piece = "\(cgmImported) CGM"
                if let e = earliestTimestamp, let l = latestTimestamp {
                    let df = DateFormatter()
                    df.dateFormat = "MMM d"
                    piece += " (\(df.string(from: e)) → \(df.string(from: l)))"
                }
                parts.append(piece)
            }
            if bolusImported > 0 { parts.append("\(bolusImported) bolus") }
            if basalImported > 0 { parts.append("\(basalImported) basal") }
            return parts.isEmpty ? "No rows matched" : parts.joined(separator: " · ")
        }
    }

    /// Top-level ingest. Detects zip vs raw csv, runs the parsers, and writes
    /// matched rows into SwiftData with dedup. Safe to call repeatedly; dedup
    /// means overlapping ranges don't double-insert.
    @MainActor
    static func importArchive(
        data: Data,
        suggestedFilename: String,
        modelContext: ModelContext
    ) throws -> ImportResult {
        print("[Glooko] importArchive: \(suggestedFilename) (\(data.count) bytes)")
        try saveRaw(data: data, suggestedFilename: suggestedFilename)

        var result = ImportResult()

        // Tighter zip detection: need full local-file-header magic (PK\x03\x04)
        // or EOCD magic (PK\x05\x06). "PK" alone is too weak.
        let header = Array(data.prefix(4))
        let isZip = header.count == 4 && header[0] == 0x50 && header[1] == 0x4B
            && (header[2] == 0x03 || header[2] == 0x05 || header[2] == 0x07)

        if isZip {
            var stats = MiniZip.ExtractStats()
            do {
                let entries = try MiniZip.extract(data, stats: &stats)
                result.extractedFilenames = entries.map { $0.filename }
                print("[Glooko] Zip extracted \(entries.count) entries (of \(stats.totalInZip) total)")
                for entry in entries {
                    print("[Glooko]   • \(entry.filename) (\(entry.data.count) bytes)")
                    let text = String(data: entry.data, encoding: .utf8)
                        ?? String(data: entry.data, encoding: .isoLatin1)
                        ?? ""
                    if text.isEmpty {
                        print("[Glooko]     decode failed, skipping")
                        result.unknownFiles.append("\(entry.filename) (couldn't decode text)")
                        continue
                    }
                    if result.sample.isEmpty {
                        result.sample = previewLines(text)
                    }
                    let beforeCGM = result.cgmImported
                    let beforeBolus = result.bolusImported
                    let beforeBasal = result.basalImported
                    ingest(text: text, filename: entry.filename, into: modelContext, result: &result)
                    let addedCGM = result.cgmImported - beforeCGM
                    let addedBolus = result.bolusImported - beforeBolus
                    let addedBasal = result.basalImported - beforeBasal
                    print("[Glooko]     → CGM:\(addedCGM) bolus:\(addedBolus) basal:\(addedBasal)")
                }
                if stats.totalInZip == 0 {
                    result.zipInfo = "Zip had 0 entries (empty export — likely no data in selected range)"
                } else if entries.isEmpty {
                    result.zipInfo = "Zip listed \(stats.totalInZip) entries, 0 extracted. Skipped: "
                        + stats.skipped.joined(separator: " | ")
                } else {
                    result.zipInfo = "Zip: \(stats.extracted)/\(stats.totalInZip) entries extracted"
                        + (stats.skipped.isEmpty ? "" : ". Skipped: \(stats.skipped.joined(separator: " | "))")
                }
            } catch {
                result.zipInfo = "Zip parse error: \(error)"
            }
        } else if let text = String(data: data, encoding: .utf8) {
            result.sample = previewLines(text)
            ingest(text: text, filename: suggestedFilename, into: modelContext, result: &result)
        } else {
            result.zipInfo = "Not a zip, not UTF-8. \(data.count) bytes starting with \(header.map { String(format: "%02x", $0) }.joined(separator: " "))"
        }

        if result.didImport {
            try? modelContext.save()
            recordSync()
        }
        return result
    }

    /// Persist the raw bytes (zip or csv) to Documents/Glooko/ for audit.
    @discardableResult
    private static func saveRaw(data: Data, suggestedFilename: String) throws -> URL {
        try saveCSV(data: data, suggestedFilename: suggestedFilename)
    }

    private static func previewLines(_ text: String) -> String {
        let preview = text
            .components(separatedBy: .newlines)
            .prefix(3)
            .joined(separator: " ⏎ ")
            .trimmingCharacters(in: .whitespaces)
        return String(preview.prefix(240))
    }

    /// Route a single CSV's text to the right parser. We try filename hints
    /// first (fastest, unambiguous), then fall back to trying every parser on
    /// the content — so a file named anything at all still gets imported if
    /// its columns look like CGM / bolus / basal data. Cross-contamination
    /// isn't a concern because each parser requires distinct column headers.
    @MainActor
    private static func ingest(
        text: String,
        filename: String,
        into modelContext: ModelContext,
        result: inout ImportResult
    ) {
        let lower = filename.lowercased()

        // Hint path: filename matches one of the three file types Glooko
        // produces. Parse that specifically.
        if lower.contains("cgm") {
            print("[Glooko] CGM file \(filename): text length=\(text.count) bytes, \(text.components(separatedBy: .newlines).count) lines")
            let rows = GlookoImporter.parseCGM(from: text)
            print("[Glooko] parseCGM produced \(rows.count) rows")
            if let first = rows.min(by: { $0.timestamp < $1.timestamp }),
               let last = rows.max(by: { $0.timestamp < $1.timestamp }) {
                print("[Glooko] CGM timespan: \(first.timestamp) → \(last.timestamp)")
            }
            if !rows.isEmpty {
                let inserted = insertCGM(rows, into: modelContext, result: &result)
                print("[Glooko] CGM inserted \(inserted) new (rest deduped)")
                result.cgmImported += inserted
                result.filesProcessed.append(filename)
                return
            }
        }
        if lower.contains("bolus") {
            let rows = GlookoImporter.parseBolus(from: text)
            if !rows.isEmpty {
                result.bolusImported += insertBolus(rows, into: modelContext)
                result.filesProcessed.append(filename)
                return
            }
        }
        if lower.contains("basal") {
            let rows = GlookoImporter.parseBasal(from: text)
            if !rows.isEmpty {
                result.basalImported += insertBasal(rows, into: modelContext)
                result.filesProcessed.append(filename)
                return
            }
        }

        // No filename hint (or hint path's parser failed) — try all three.
        // First parser to return rows wins.
        let cgm = GlookoImporter.parseCGM(from: text)
        if !cgm.isEmpty {
            result.cgmImported += insertCGM(cgm, into: modelContext, result: &result)
            result.filesProcessed.append(filename)
            return
        }
        let bolus = GlookoImporter.parseBolus(from: text)
        if !bolus.isEmpty {
            result.bolusImported += insertBolus(bolus, into: modelContext)
            result.filesProcessed.append(filename)
            return
        }
        let basal = GlookoImporter.parseBasal(from: text)
        if !basal.isEmpty {
            result.basalImported += insertBasal(basal, into: modelContext)
            result.filesProcessed.append(filename)
            return
        }
        result.unknownFiles.append(filename)
    }

    @MainActor
    private static func insertCGM(
        _ rows: [GlookoImporter.CGMRow],
        into ctx: ModelContext,
        result: inout ImportResult
    ) -> Int {
        let existing = (try? ctx.fetch(FetchDescriptor<GlucoseReading>())) ?? []
        // Dedup at integer-second precision. Date equality at full nanosecond
        // precision is brittle — re-parses of the same CSV can produce dates
        // that round-trip differently and defeat Set<Date> lookups.
        let seen = Set(existing.map { Int($0.timestamp.timeIntervalSince1970) })
        var previous: Int? = existing
            .sorted(by: { $0.timestamp < $1.timestamp }).last?.value
        var inserted = 0
        for row in rows.sorted(by: { $0.timestamp < $1.timestamp })
        where !seen.contains(Int(row.timestamp.timeIntervalSince1970)) {
            ctx.insert(GlucoseReading(
                value: row.value,
                timestamp: row.timestamp,
                trendArrow: GlookoImporter.inferTrend(current: row.value, previous: previous),
                source: .cgm,
                importOrigin: "glooko"
            ))
            previous = row.value
            inserted += 1
            // Track the actual date range of new rows so the success banner
            // can show "2026-04-09 → 2026-04-22" — tells us at a glance
            // whether Glooko really gave us 2 weeks or just today.
            if result.earliestTimestamp == nil || row.timestamp < result.earliestTimestamp! {
                result.earliestTimestamp = row.timestamp
            }
            if result.latestTimestamp == nil || row.timestamp > result.latestTimestamp! {
                result.latestTimestamp = row.timestamp
            }
        }
        return inserted
    }

    @MainActor
    private static func insertBolus(
        _ rows: [GlookoImporter.BolusRow], into ctx: ModelContext
    ) -> Int {
        // Dedup by (timestamp, units) so a re-import with different CSVs
        // doesn't duplicate a bolus — but different bolus amounts at the same
        // moment still count as distinct events.
        let existing = (try? ctx.fetch(FetchDescriptor<InsulinEntry>(
            predicate: #Predicate { $0.kindRaw == "bolus" }
        ))) ?? []
        let seen = Set(existing.map { "\(Int($0.timestamp.timeIntervalSince1970))|\($0.units)" })
        var inserted = 0
        for row in rows {
            let key = "\(Int(row.timestamp.timeIntervalSince1970))|\(row.insulinDelivered)"
            if seen.contains(key) { continue }
            ctx.insert(InsulinEntry(
                timestamp: row.timestamp,
                units: row.insulinDelivered,
                kind: .bolus,
                carbs: row.carbs
            ))
            inserted += 1
        }
        return inserted
    }

    @MainActor
    private static func insertBasal(
        _ rows: [GlookoImporter.BasalRow], into ctx: ModelContext
    ) -> Int {
        let existing = (try? ctx.fetch(FetchDescriptor<InsulinEntry>(
            predicate: #Predicate { $0.kindRaw == "basal" }
        ))) ?? []
        let seen = Set(existing.map { Int($0.timestamp.timeIntervalSince1970) })
        var inserted = 0
        for row in rows where !seen.contains(Int(row.timestamp.timeIntervalSince1970)) {
            ctx.insert(InsulinEntry(
                timestamp: row.timestamp,
                units: row.rate,
                kind: .basal,
                durationSeconds: row.durationSeconds
            ))
            inserted += 1
        }
        return inserted
    }

    // MARK: - Sync range

    /// Time window offered in Glooko's Export to CSV dialog. Raw value must
    /// exactly match the text Glooko renders in the dropdown option, since
    /// that's how the injected JS selects it.
    enum SyncRange: String, CaseIterable, Identifiable {
        case d1 = "1 day"
        case w1 = "1 week"
        case w2 = "2 weeks"
        case d30 = "30 days"
        case d90 = "90 days"

        var id: String { rawValue }
        var shortLabel: String {
            switch self {
            case .d1: "1d"
            case .w1: "1w"
            case .w2: "2w"
            case .d30: "30d"
            case .d90: "90d"
            }
        }
    }

    // MARK: - Injected JavaScript (shared between login sheet + silent sync)

    /// Captures Blob-based downloads across every plausible trigger path:
    /// anchor.click(), user-simulated click events on anchors with blob: href,
    /// `window.open(blobURL)`, and `window.location = blobURL`. Reads the
    /// Blob as base64 and posts it to Swift via `glookoBlob`.
    static let blobInterceptorJS = """
    (function() {
        if (window.__glookoBlobHook) return;
        window.__glookoBlobHook = true;
        var pending = new Map();

        function postBlob(blob, name) {
            try {
                var reader = new FileReader();
                reader.onload = function() {
                    var dataUrl = reader.result || '';
                    var comma = dataUrl.indexOf(',');
                    var b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
                    try {
                        window.webkit.messageHandlers.glookoBlob.postMessage({
                            filename: name || 'glooko.csv', base64: b64
                        });
                    } catch (e) {}
                };
                reader.readAsDataURL(blob);
            } catch (e) {}
        }

        function consumeBlobURL(url, fallbackName) {
            if (!url || !pending.has(url)) return false;
            var blob = pending.get(url);
            pending.delete(url);
            postBlob(blob, fallbackName);
            return true;
        }

        // 1) Remember blobs as they're minted.
        var origCreate = URL.createObjectURL;
        URL.createObjectURL = function(obj) {
            var u = origCreate.call(URL, obj);
            try { if (obj instanceof Blob) pending.set(u, obj); } catch (e) {}
            return u;
        };

        // 2) Programmatic anchor.click()
        var origClick = HTMLAnchorElement.prototype.click;
        HTMLAnchorElement.prototype.click = function() {
            try {
                var href = this.getAttribute('href') || this.href || '';
                var name = this.getAttribute('download') || 'glooko.csv';
                consumeBlobURL(href, name);
            } catch (e) {}
            return origClick.apply(this, arguments);
        };

        // 3) User-like click event bubbling (dispatchEvent, real pointer).
        document.addEventListener('click', function(e) {
            try {
                var el = e.target;
                while (el && el !== document && el.tagName !== 'A') el = el.parentNode;
                if (!el || el.tagName !== 'A') return;
                var href = el.getAttribute('href') || el.href || '';
                var name = el.getAttribute('download') || 'glooko.csv';
                consumeBlobURL(href, name);
            } catch (e) {}
        }, true);

        // 4) window.open(blob:url)
        var origOpen = window.open;
        window.open = function(url) {
            try {
                if (typeof url === 'string' && consumeBlobURL(url, 'glooko.csv')) {
                    return null;
                }
            } catch (e) {}
            return origOpen.apply(window, arguments);
        };

        // 5) window.location = blob:url (and .href / .assign / .replace).
        try {
            var loc = window.location;
            var origAssign = loc.assign && loc.assign.bind(loc);
            var origReplace = loc.replace && loc.replace.bind(loc);
            if (origAssign) {
                loc.assign = function(url) {
                    if (consumeBlobURL(url, 'glooko.csv')) return;
                    return origAssign(url);
                };
            }
            if (origReplace) {
                loc.replace = function(url) {
                    if (consumeBlobURL(url, 'glooko.csv')) return;
                    return origReplace(url);
                };
            }
        } catch (e) {}
    })();
    """

    /// Installs a MutationObserver that finds Glooko's Export to CSV button by
    /// class-prefix or visible text and clicks it as soon as it mounts. Falls
    /// back to a 20s / 500ms polling loop so client-side routing re-renders
    /// still get picked up.
    ///
    /// Also walks shadow roots and same-origin iframes so Portal-mounted or
    /// sandboxed buttons still get found.
    ///
    /// Reports what it sees back via the `glookoDiag` WKScriptMessageHandler
    /// so Swift can surface diagnostic info when auto-click fails.
    static let autoExportJS = """
    (function() {
        if (window.__glookoExportRunner) return;
        window.__glookoExportRunner = true;
        // State machine:
        //   'findButton'    — search page for "Export to CSV" button, click it
        //   'waitModal'     — wait for export dialog to appear
        //   'openDropdown'  — open the range dropdown
        //   'selectOption'  — click option matching window.__glookoRange
        //   'confirmExport' — click the final Export button
        //   'done'          — CSV capture path takes over
        var state = 'findButton';
        var triggered = false;
        var lastReport = 0;
        var rangeStableTicks = 0;

        function allCandidates(root) {
            var out = [];
            try {
                root.querySelectorAll('button, a, [role="button"]').forEach(function(el) {
                    out.push(el);
                });
            } catch (e) {}
            // Walk shadow roots.
            try {
                root.querySelectorAll('*').forEach(function(el) {
                    if (el.shadowRoot) {
                        out = out.concat(allCandidates(el.shadowRoot));
                    }
                });
            } catch (e) {}
            return out;
        }

        function allFrames() {
            var frames = [document];
            try {
                document.querySelectorAll('iframe').forEach(function(f) {
                    try { if (f.contentDocument) frames.push(f.contentDocument); } catch (e) {}
                });
            } catch (e) {}
            return frames;
        }

        function findExportButton() {
            var frames = allFrames();
            for (var f = 0; f < frames.length; f++) {
                var cands = allCandidates(frames[f]);
                for (var i = 0; i < cands.length; i++) {
                    var el = cands[i];
                    var cls = (typeof el.className === 'string')
                        ? el.className
                        : (el.getAttribute && el.getAttribute('class')) || '';
                    var txt = (el.innerText || el.textContent || '').trim();
                    var alt = '';
                    try {
                        var img = el.querySelector && el.querySelector('img');
                        if (img) alt = img.getAttribute('alt') || '';
                    } catch (e) {}
                    if (cls.indexOf('ExportToCSVButton') !== -1 ||
                        /Export to CSV/i.test(txt) ||
                        /exportToCSV/i.test(alt)) {
                        return el;
                    }
                }
            }
            return null;
        }

        function clickElement(el) {
            try { el.scrollIntoView({block: 'center'}); } catch (e) {}
            // Defer to fireFullClick (defined below) so React handlers get the
            // full pointer/mouse dance, not just a bare click event.
            try { fireFullClick(el); }
            catch (e) { try { el.click(); } catch (e2) {} }
        }

        // Export-to-CSV dialog (stage 2+). The header has a stable data-testid,
        // and we walk up to the nearest dialog/modal container so all modal-
        // scoped queries are contained.
        function findModal() {
            var frames = allFrames();
            for (var f = 0; f < frames.length; f++) {
                try {
                    var header = frames[f].querySelector(
                        '[data-testid="dialog-header-export-to-csv"]'
                    );
                    if (!header) continue;
                    return header.closest('[role="dialog"]') ||
                           header.closest('[class*="modal" i]') ||
                           header.closest('[class*="Dialog" i]') ||
                           (header.parentNode && header.parentNode.parentNode) ||
                           header;
                } catch (e) {}
            }
            return null;
        }

        function currentDropdownValue(modal) {
            try {
                var el = modal.querySelector('.dropdown__single-value');
                return el ? el.textContent.trim() : null;
            } catch (e) { return null; }
        }

        // react-select opens on pointerdown/mousedown — fire both, plus a
        // click fallback, so it works across versions.
        function openDropdown(modal) {
            try {
                var control = modal.querySelector('.dropdown__control');
                if (!control) return false;
                fireFullClick(control);
                return true;
            } catch (e) { return false; }
        }

        function selectOption(labelText) {
            try {
                // Options render in a portal, so query document-wide.
                var opts = document.querySelectorAll(
                    '.dropdown__option, [role="option"]'
                );
                for (var i = 0; i < opts.length; i++) {
                    if (opts[i].textContent.trim() === labelText) {
                        fireFullClick(opts[i]);
                        return true;
                    }
                }
            } catch (e) {}
            return false;
        }

        /// Dispatches pointerdown → mousedown → pointerup → mouseup → click,
        /// all bubbling, primary button, from the element's center. react-select
        /// uses onPointerDown for control-open and onMouseDown for option-select,
        /// depending on version; firing both covers all paths.
        function fireFullClick(el) {
            var rect = el.getBoundingClientRect();
            var cx = rect.left + rect.width / 2;
            var cy = rect.top + rect.height / 2;
            var common = {
                bubbles: true, cancelable: true, view: window,
                button: 0, buttons: 1, clientX: cx, clientY: cy
            };
            try { el.dispatchEvent(new PointerEvent('pointerdown', Object.assign({ pointerType: 'mouse' }, common))); } catch (e) {}
            el.dispatchEvent(new MouseEvent('mousedown', common));
            try { el.dispatchEvent(new PointerEvent('pointerup', Object.assign({ pointerType: 'mouse' }, common))); } catch (e) {}
            el.dispatchEvent(new MouseEvent('mouseup', common));
            el.dispatchEvent(new MouseEvent('click', common));
        }

        function clickFinalExport(modal) {
            try {
                var btn = modal.querySelector('[data-testid="button-export-to-csv-export"]')
                    || document.querySelector('[data-testid="button-export-to-csv-export"]');
                if (!btn) return false;
                clickElement(btn);
                return true;
            } catch (e) {}
            return false;
        }

        function tick() {
            if (triggered) return;
            var desiredRange = String(window.__glookoRange || '90 days').trim();

            if (state === 'findButton') {
                // Idle until Swift flips the ready flag (sessionStorage backs
                // the window global so SPA route changes don't clear it).
                var ready = window.__glookoReady;
                if (!ready) {
                    try { ready = sessionStorage.getItem('glookoReady') === '1'; } catch (e) {}
                }
                if (!ready) return;
                window.__glookoReady = true;
                var btn = findExportButton();
                if (btn) {
                    clickElement(btn);
                    state = 'waitModal';
                }
                return;
            }

            var modal = findModal();
            if (!modal) return;

            if (state === 'waitModal') {
                var current = currentDropdownValue(modal);
                if (current === desiredRange) {
                    state = 'confirmExport';
                } else if (openDropdown(modal)) {
                    state = 'selectOption';
                }
                return;
            }

            if (state === 'selectOption') {
                if (selectOption(desiredRange)) {
                    state = 'confirmExport';
                }
                return;
            }

            if (state === 'confirmExport') {
                // Wait until the dropdown actually reflects the desired value
                // for TWO consecutive ticks — react-select sometimes flashes
                // the new value then reverts, so require stability.
                if (currentDropdownValue(modal) !== desiredRange) {
                    rangeStableTicks = 0;
                    // Fall back to re-opening if the value drifted away.
                    state = 'waitModal';
                    return;
                }
                rangeStableTicks++;
                if (rangeStableTicks < 2) return;
                if (clickFinalExport(modal)) {
                    triggered = true;
                    state = 'done';
                }
            }
        }

        function reportDiagnostics(reason) {
            // Throttle: don't spam.
            var now = Date.now();
            if (now - lastReport < 2000) return;
            lastReport = now;
            try {
                var frames = allFrames();
                var summary = [];
                for (var f = 0; f < frames.length; f++) {
                    var cands = allCandidates(frames[f]);
                    for (var i = 0; i < cands.length && summary.length < 40; i++) {
                        var el = cands[i];
                        var cls = (typeof el.className === 'string')
                            ? el.className
                            : (el.getAttribute && el.getAttribute('class')) || '';
                        var txt = (el.innerText || el.textContent || '').trim().slice(0, 40);
                        summary.push({ cls: String(cls).slice(0, 60), txt: txt });
                    }
                }
                window.webkit.messageHandlers.glookoDiag.postMessage({
                    reason: reason,
                    url: location.href,
                    title: document.title,
                    buttons: summary
                });
            } catch (e) {}
        }

        var observer = null;
        try {
            observer = new MutationObserver(tick);
            observer.observe(document.documentElement, { childList: true, subtree: true });
        } catch (e) {}

        tick();

        // Persistent 2-minute watcher so SPA route changes (React Router,
        // history.pushState) still get picked up without needing a full page
        // reload to re-inject this script.
        var ticks = 0;
        var interval = setInterval(function() {
            ticks++;
            if (triggered) {
                clearInterval(interval);
                try { if (observer) observer.disconnect(); } catch (e) {}
                return;
            }
            if (ticks > 240) {
                clearInterval(interval);
                try { if (observer) observer.disconnect(); } catch (e) {}
                reportDiagnostics('timeout:' + state);
                return;
            }
            tick();
            if (ticks === 4 || ticks === 20 || ticks === 80) {
                reportDiagnostics('tick:' + ticks + ':' + state);
            }
        }, 500);
    })();
    """
}
