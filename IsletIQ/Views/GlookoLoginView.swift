import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
import WebKit
#endif

/// Glooko connect flow. Fully automated:
///
/// 1. User logs in on `my.glooko.com` via embedded `WKWebView`.
/// 2. Once a `_glooko_session` cookie appears, we hide the WebView behind a
///    "Connected / importing..." progress overlay and inject JavaScript that
///    auto-clicks Glooko's "Export to CSV" button as soon as it appears on
///    the page (MutationObserver + polling fallback).
/// 3. The CSV download is intercepted (HTTP attachment *or* client-side Blob),
///    saved to Documents, parsed, and CGM rows are imported into SwiftData
///    (`GlucoseReading`) with dedup by timestamp.
/// 4. On success, the sheet auto-dismisses after a brief "Connected ✓" flash.
///
/// Credentials never leave Glooko's page; we only see session cookies.
struct GlookoLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("glooko_sync_range") private var rangeRaw: String = GlookoClient.SyncRange.d90.rawValue
    @State private var phase: Phase = .idle
    @State private var statusText: String = ""
    @State private var errorText: String?
    @State private var importedRows: Int = 0
    @State private var timeoutTask: Task<Void, Never>?
    @State private var syncCommand: Int = 0
    @State private var signedIn: Bool = false
    @State private var lastJSState: String = ""
    @State private var copiedConfirmation: Bool = false

    enum Phase { case idle, importing, success, failed }

    private var selectedRange: GlookoClient.SyncRange {
        get { GlookoClient.SyncRange(rawValue: rangeRaw) ?? .d90 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBanner
                controlBar

                #if canImport(UIKit)
                ZStack {
                    GlookoWebView(
                        url: GlookoClient.loginURL,
                        rangeLabel: rangeRaw,
                        syncCommand: syncCommand,
                        onLoginDetected: handleLoginDetected,
                        onCSVCaptured: handleCSV,
                        onDiagnostic: { diag in
                            if let state = Self.extractState(from: diag) {
                                lastJSState = state
                            }
                            if phase == .failed { statusText = diag }
                        },
                        onError: { err in
                            if phase != .idle { errorText = err }
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)

                    // Cover the WebView with our custom loading UI from the
                    // moment Sync Now is tapped until sync resolves. Before
                    // that, the user sees Glooko's own page for login +
                    // optional browsing — the moment auto-sync kicks in we
                    // hide the dashboard.
                    if phase != .idle {
                        signedInOverlay
                            .transition(.opacity)
                    }
                }
                #else
                unsupportedPlatform
                #endif

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(Theme.high)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Connect Glooko")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .importing ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    /// Range picker is always visible so the user can set it before logging
    /// in. Sync Now is only enabled once we've detected a Glooko session —
    /// tapping it before login would just dump noise from the sign-in page.
    private var controlBar: some View {
        HStack(spacing: 10) {
            Picker("Range", selection: Binding(
                get: { GlookoClient.SyncRange(rawValue: rangeRaw) ?? .d90 },
                set: { rangeRaw = $0.rawValue }
            )) {
                ForEach(GlookoClient.SyncRange.allCases) { r in
                    Text(r.shortLabel).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            let canSync = signedIn && phase != .importing
            Button {
                startImport()
            } label: {
                HStack(spacing: 4) {
                    if phase == .importing {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    }
                    Text(!signedIn ? "Sign in first"
                         : phase == .importing ? "Syncing"
                         : "Sync Now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    canSync ? Theme.primary : Theme.primary.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSync)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bg)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch phase {
        case .idle:
            bannerRow(
                icon: signedIn ? "checkmark.shield.fill" : "lock.shield.fill",
                iconColor: signedIn ? Theme.normal : Theme.primary,
                title: signedIn ? "Signed in — ready to sync" : "Sign in on Glooko's site",
                subtitle: signedIn
                    ? "Pick a range and tap Sync Now. Auto-export runs below."
                    : "Log in to Glooko below. Pick your range anytime, then tap Sync Now.",
                background: Theme.cardBg
            )
        case .importing:
            bannerRow(
                icon: "square.and.arrow.down.fill",
                iconColor: Theme.primary,
                title: "Importing \(selectedRange.rawValue) of Glooko data",
                subtitle: statusText.isEmpty
                    ? "Clicking Export, selecting range, downloading CSV..."
                    : statusText,
                background: Theme.cardBg
            )
        case .success:
            bannerRow(
                icon: "checkmark.circle.fill",
                iconColor: Theme.normal,
                title: "Imported",
                subtitle: statusText,
                background: Theme.normal.opacity(0.12)
            )
        case .failed:
            bannerRow(
                icon: "exclamationmark.triangle.fill",
                iconColor: Theme.high,
                title: "Couldn't finish import",
                subtitle: statusText,
                background: Theme.high.opacity(0.1)
            )
        }
    }

    /// Full-screen card shown over the WebView during sync so the user sees
    /// a clean progress UI instead of Glooko's dashboard. WebView stays
    /// running behind it — injected JS drives the export invisibly.
    private var signedInOverlay: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                GlookoSyncLoader(
                    phase: phase,
                    primary: Theme.primary,
                    success: Theme.normal,
                    failure: Theme.high
                )
                Text(overlayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if let sub = overlaySubtitle {
                    ScrollView {
                        Text(sub)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 32)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                }
                if phase == .failed {
                    HStack(spacing: 10) {
                        Button {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = overlaySubtitle ?? ""
                            let gen = UINotificationFeedbackGenerator()
                            gen.notificationOccurred(.success)
                            #endif
                            copiedConfirmation = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2))
                                copiedConfirmation = false
                            }
                        } label: {
                            Label(copiedConfirmation ? "Copied" : "Copy",
                                  systemImage: copiedConfirmation ? "checkmark" : "doc.on.clipboard")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(copiedConfirmation ? Theme.normal : Theme.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    (copiedConfirmation ? Theme.normal : Theme.primary).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        ShareLink(item: overlaySubtitle ?? "") {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Theme.primary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var overlayTitle: String {
        switch phase {
        case .importing: return "Importing \(selectedRange.rawValue) of Glooko data"
        case .success: return "Imported"
        case .failed: return "Couldn't finish import"
        case .idle: return ""
        }
    }

    private var overlaySubtitle: String? {
        switch phase {
        case .importing: return "Opening report, selecting range, downloading CSV..."
        case .success: return statusText.isEmpty ? nil : statusText
        case .failed: return statusText.isEmpty ? "Tap Sync Now to try again." : statusText
        case .idle: return nil
        }
    }

    private func bannerRow(icon: String, iconColor: Color, title: String,
                           subtitle: String, background: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(background)
    }

    // MARK: - Phase transitions

    private func handleLoginDetected() {
        GlookoClient.markAuthenticated()
        signedIn = true
    }

    /// User tapped "Sync Now" — flip the JS ready flag via syncCommand,
    /// transition to the importing state, and arm the fallback timeout.
    private func startImport() {
        phase = .importing
        statusText = ""
        errorText = nil
        syncCommand += 1

        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            if phase == .importing {
                phase = .failed
                statusText = Self.failureHint(forState: lastJSState)
            }
        }
    }

    /// Human-readable explanation of where the JS state machine got stuck.
    static func failureHint(forState state: String) -> String {
        switch state {
        case "findButton":
            return "Couldn't find the Export to CSV button. Finish logging in, navigate to a Glooko report, then tap Sync Now again."
        case "waitModal":
            return "Clicked Export but the dialog didn't open. Try tapping Sync Now again, or click Export inside Glooko manually."
        case "selectOption":
            return "Opened the range dropdown but couldn't select \(state). Tap Sync Now again, or pick the range manually in Glooko."
        case "confirmExport":
            return "Set the range but the final Export button didn't click. Tap it inside Glooko manually."
        default:
            return "Auto-export didn't complete. Make sure you're logged in and on a Glooko report page, then tap Sync Now again."
        }
    }

    static func extractState(from diag: String) -> String? {
        // Format is "URL: ... · N buttons. Top: ..." OR "timeout:state" OR
        // "tick:N:state" depending on source. The state machine diag strings
        // that include a state are the second two forms.
        let parts = diag.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        if parts[0] == "timeout", parts.count >= 2 {
            return String(parts[1])
        }
        if parts[0] == "tick", parts.count >= 3 {
            return String(parts[2])
        }
        return nil
    }

    private func handleCSV(data: Data, filename: String) {
        do {
            let result = try GlookoClient.importArchive(
                data: data,
                suggestedFilename: filename,
                modelContext: modelContext
            )

            importedRows += result.cgmImported + result.bolusImported + result.basalImported
            timeoutTask?.cancel()

            if result.didImport {
                phase = .success
                let filesNote = result.filesProcessed.isEmpty
                    ? ""
                    : " from \(result.filesProcessed.count) file\(result.filesProcessed.count == 1 ? "" : "s")"
                statusText = result.summary + filesNote
                errorText = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.8))
                    dismiss()
                }
            } else {
                phase = .failed
                let sizeLabel = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                let zipNote = result.zipInfo.map { " • \($0)" } ?? ""

                // Prefer showing what MiniZip actually extracted — even if the
                // per-entry pipeline dropped them, we want to see the real
                // filenames so we know whether the issue is extraction or
                // parsing.
                let filesList: String
                if !result.extractedFilenames.isEmpty {
                    filesList = "Files: " + result.extractedFilenames.prefix(6).joined(separator: ", ")
                } else {
                    let files = result.filesProcessed + result.unknownFiles
                    filesList = files.isEmpty ? "(no CSVs inside)" : files.joined(separator: ", ")
                }
                statusText = "Got \(filename) (\(sizeLabel)).\(zipNote) \(filesList). First lines: \(result.sample.isEmpty ? "(empty)" : result.sample)"
                errorText = nil
            }
        } catch {
            phase = .failed
            statusText = "Couldn't save export."
            errorText = error.localizedDescription
        }
    }

    #if !canImport(UIKit)
    private var unsupportedPlatform: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text("Connect Glooko from the iPhone app.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif
}

/// Pulsing-ring loader shown over the WebView during sync. Simple custom
/// animation so the state feels distinct from a generic `ProgressView`.
private struct GlookoSyncLoader: View {
    let phase: GlookoLoginView.Phase
    let primary: Color
    let success: Color
    let failure: Color
    @State private var pulse: CGFloat = 0

    var body: some View {
        ZStack {
            // Two outward-pulsing rings (animating).
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .strokeBorder(ringColor.opacity(0.5 - Double(i) * 0.2), lineWidth: 2)
                    .frame(width: 90, height: 90)
                    .scaleEffect(phase == .importing ? (1 + pulse + CGFloat(i) * 0.25) : 1)
                    .opacity(phase == .importing ? (1 - pulse) : 1)
            }
            // Center disc with phase-appropriate icon.
            Circle()
                .fill(ringColor.opacity(0.12))
                .frame(width: 90, height: 90)
                .overlay(
                    Image(systemName: centerIcon)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(ringColor)
                )
        }
        .frame(width: 150, height: 150)
        .onAppear { startPulse() }
        .onChange(of: phase) { _, _ in startPulse() }
    }

    private var ringColor: Color {
        switch phase {
        case .success: return success
        case .failed: return failure
        default: return primary
        }
    }

    private var centerIcon: String {
        switch phase {
        case .success: return "checkmark"
        case .failed: return "exclamationmark"
        default: return "arrow.down"
        }
    }

    private func startPulse() {
        pulse = 0
        guard phase == .importing else { return }
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
            pulse = 1
        }
    }
}

#if canImport(UIKit)
private struct GlookoWebView: UIViewRepresentable {
    let url: URL
    let rangeLabel: String
    let syncCommand: Int
    let onLoginDetected: () -> Void
    let onCSVCaptured: (Data, String) -> Void
    let onDiagnostic: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // Seed window.__glookoRange before anything else runs so the export
        // auto-runner picks up the user's chosen range on first tick.
        let rangeScript = WKUserScript(
            source: "window.__glookoRange = '\(Self.escape(rangeLabel))';",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(rangeScript)

        // Blob-download interceptor — runs at document start so client-side
        // CSV generation (Blob + <a download>.click()) round-trips back to Swift.
        let blobScript = WKUserScript(
            source: GlookoClient.blobInterceptorJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(blobScript)

        // Auto-export watcher — runs at document-end on every real navigation,
        // and stays alive for 2 minutes watching the DOM so SPA route changes
        // within Glooko's React app still get picked up.
        let exportScript = WKUserScript(
            source: GlookoClient.autoExportJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(exportScript)

        config.userContentController.add(context.coordinator, name: "glookoBlob")
        config.userContentController.add(context.coordinator, name: "glookoDiag")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        context.coordinator.webView = webView
        context.coordinator.lastRange = rangeLabel
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Live-update the JS global if the user changes the range picker mid
        // flow — so they can switch before the modal appears.
        if context.coordinator.lastRange != rangeLabel {
            context.coordinator.lastRange = rangeLabel
            webView.evaluateJavaScript(
                "window.__glookoRange = '\(Self.escape(rangeLabel))';"
            ) { _, _ in }
        }
        // When syncCommand increments, flip the JS ready flag. Write to BOTH
        // window and sessionStorage so the flag survives SPA route changes
        // inside glooko.com (window resets on nav, sessionStorage doesn't).
        if context.coordinator.lastSyncCommand != syncCommand {
            context.coordinator.lastSyncCommand = syncCommand
            if syncCommand > 0 {
                let js = """
                try { sessionStorage.setItem('glookoReady', '1'); } catch (e) {}
                window.__glookoReady = true;
                """
                webView.evaluateJavaScript(js) { _, _ in }
            }
        }
    }

    /// Escape single quotes and backslashes for safe JS string-literal interpolation.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "'", with: "\\'")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate, WKScriptMessageHandler {
        let parent: GlookoWebView
        private var didReportLogin = false
        private var pendingDownloadDestination: URL?
        private var loginPollTimer: Timer?
        weak var webView: WKWebView?
        var lastRange: String = ""
        var lastSyncCommand: Int = 0

        init(_ parent: GlookoWebView) {
            self.parent = parent
            super.init()
            startLoginPolling()
        }

        deinit {
            loginPollTimer?.invalidate()
        }

        /// Glooko's dashboard navigation often uses `history.pushState`, which
        /// doesn't fire WKNavigationDelegate's `didFinish`. Poll the WebView
        /// URL + cookie store every 2s as a backup login-detection path.
        private func startLoginPolling() {
            loginPollTimer?.invalidate()
            loginPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkLoginState()
            }
        }

        private func checkLoginState() {
            guard !didReportLogin, let webView, let url = webView.url,
                  isPostLoginURL(url) else { return }
            // URL-only detection: if we're on glooko.com at a non-auth path,
            // the user is signed in (the dashboard won't render otherwise —
            // Glooko redirects back to /users/sign_in for unauthenticated
            // requests). Cookie-name matching was too brittle across regions.
            didReportLogin = true
            DispatchQueue.main.async { self.parent.onLoginDetected() }
        }

        // MARK: - Login detection + auto-export kickoff

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            guard let url = webView.url, isPostLoginURL(url) else { return }

            if !didReportLogin {
                didReportLogin = true
                parent.onLoginDetected()
            }
            // Re-arm the export script on every navigation in case the prior
            // page tore down its observer (SPA or full reload both covered).
            startAutoExport(on: webView)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            DispatchQueue.main.async { self.parent.onError(error.localizedDescription) }
        }

        private func isPostLoginURL(_ url: URL) -> Bool {
            guard let host = url.host, host.contains("glooko.com") else { return false }
            let authPrefixes = [
                "/users/sign_in", "/users/sign_up", "/users/password",
                "/users/confirmation", "/users/two_factor", "/users/unlock",
            ]
            return !authPrefixes.contains(where: { url.path.hasPrefix($0) })
        }

        private func startAutoExport(on webView: WKWebView) {
            webView.evaluateJavaScript(GlookoClient.autoExportJS) { _, _ in }
        }

        // MARK: - HTTP download capture (Content-Disposition: attachment)

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let http = navigationResponse.response as? HTTPURLResponse {
                let disposition = (http.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
                let mime = (http.mimeType ?? "").lowercased()
                if disposition.contains("attachment") || mime.contains("csv") {
                    decisionHandler(.download)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_" + suggestedFilename)
            pendingDownloadDestination = dest
            completionHandler(dest)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let url = pendingDownloadDestination else { return }
            defer {
                try? FileManager.default.removeItem(at: url)
                pendingDownloadDestination = nil
            }
            guard let data = try? Data(contentsOf: url) else { return }
            let stripped = url.lastPathComponent
                .components(separatedBy: "_")
                .dropFirst()
                .joined(separator: "_")
            let name = stripped.isEmpty ? "glooko.csv" : stripped
            DispatchQueue.main.async { self.parent.onCSVCaptured(data, name) }
        }

        func download(_ download: WKDownload,
                      didFailWithError error: Error,
                      resumeData: Data?) {
            DispatchQueue.main.async {
                self.parent.onError("Download failed: \(error.localizedDescription)")
            }
        }

        // MARK: - Blob download capture (JS bridge)

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "glookoBlob",
               let body = message.body as? [String: Any],
               let b64 = body["base64"] as? String,
               let data = Data(base64Encoded: b64) {
                let filename = (body["filename"] as? String) ?? "glooko.csv"
                DispatchQueue.main.async { self.parent.onCSVCaptured(data, filename) }
                return
            }
            if message.name == "glookoDiag",
               let body = message.body as? [String: Any] {
                let url = (body["url"] as? String) ?? "?"
                let buttons = (body["buttons"] as? [[String: Any]]) ?? []
                let sample = buttons.prefix(5).map { b -> String in
                    let cls = (b["cls"] as? String) ?? ""
                    let txt = (b["txt"] as? String) ?? ""
                    return txt.isEmpty ? cls : "\(txt) [\(cls.prefix(30))]"
                }.joined(separator: " · ")
                let msg = "URL: \(URL(string: url)?.path ?? url) · \(buttons.count) buttons. Top: \(sample)"
                DispatchQueue.main.async { self.parent.onDiagnostic(msg) }
            }
        }
    }

}
#endif
