import Foundation

/// Parsers for Glooko's CSV exports. Glooko's "Export to CSV" produces a ZIP
/// archive containing several CSVs (cgm_data_1.csv, bolus_data_1.csv,
/// basal_data_1.csv, ...). Each file's column layout varies with device and
/// export date, so these parsers auto-detect the relevant columns by header
/// text rather than relying on fixed positions, and try a range of date
/// formats to cover Glooko's US/ISO/zoned variants.
struct GlookoImporter {

    // MARK: - Row types

    struct CGMRow {
        let timestamp: Date
        let value: Int
    }

    struct BolusRow {
        let timestamp: Date
        /// Units of insulin delivered.
        let insulinDelivered: Double
        /// Carbs entered with the bolus (0 if none).
        let carbs: Double
    }

    struct BasalRow {
        let timestamp: Date
        /// Units per hour.
        let rate: Double
        /// Duration in seconds (0 if unknown).
        let durationSeconds: Double
    }

    struct InsulinDayRow {
        let timestamp: Date
        let totalBolus: Double
        let totalInsulin: Double
        let totalBasal: Double
    }

    // MARK: - CGM

    /// Parses a Glooko CGM CSV. Auto-detects the timestamp column (header
    /// contains "time" or "date") and glucose column (contains "glucose",
    /// "mg/dl", "mmol", "cgm", or "bg"). Handles mmol/L → mg/dL conversion.
    static func parseCGM(from csvString: String) -> [CGMRow] {
        guard let table = parseTable(csvString),
              let tsIdx = findColumn(in: table.header, keywords: ["timestamp", "time", "date"]),
              let valIdx = findColumn(in: table.header, keywords: [
                  "glucose value", "cgm glucose value", "glucose", "cgm", "mg/dl", "mmol", "bg value", "bg "
              ])
        else { return [] }

        let isMmol = table.header[valIdx].lowercased().contains("mmol")
        var rows: [CGMRow] = []
        for cols in table.rows {
            guard cols.count > max(tsIdx, valIdx),
                  let ts = parseFlexibleDate(cols[tsIdx]),
                  let raw = Double(cols[valIdx]) else { continue }
            let mgdl = isMmol ? Int((raw * 18.0182).rounded()) : Int(raw.rounded())
            // Sanity: drop sensor glitch rows that don't look like a CGM value.
            guard mgdl >= 30, mgdl <= 600 else { continue }
            rows.append(CGMRow(timestamp: ts, value: mgdl))
        }
        return rows
    }

    // MARK: - Bolus

    /// Parses Glooko's bolus CSV. Looks for a units column ("bolus volume
    /// delivered", "units delivered", "insulin", "(u)") and an optional
    /// carbs column ("carbs", "grams").
    static func parseBolus(from csvString: String) -> [BolusRow] {
        guard let table = parseTable(csvString),
              let tsIdx = findColumn(in: table.header, keywords: ["timestamp", "time", "date"]),
              let unitsIdx = findColumn(in: table.header, keywords: [
                  "bolus volume delivered", "volume delivered", "units delivered",
                  "bolus (u)", "insulin (u)", "insulin delivered", "bolus amount", "units"
              ])
        else { return [] }

        let carbsIdx = findColumn(in: table.header, keywords: ["carbs", "carbohydrate", "grams"])
        var rows: [BolusRow] = []
        for cols in table.rows {
            guard cols.count > max(tsIdx, unitsIdx),
                  let ts = parseFlexibleDate(cols[tsIdx]),
                  let units = Double(cols[unitsIdx]),
                  units > 0 else { continue }
            let carbs: Double = {
                if let ci = carbsIdx, cols.count > ci { return Double(cols[ci]) ?? 0 }
                return 0
            }()
            rows.append(BolusRow(timestamp: ts, insulinDelivered: units, carbs: carbs))
        }
        return rows
    }

    // MARK: - Basal

    /// Parses Glooko's basal CSV — sparse segments of u/hr that apply until the
    /// next row. Reads the "Rate (U/hr)" / "Basal Rate" column and an optional
    /// "Duration" column (seconds or minutes).
    static func parseBasal(from csvString: String) -> [BasalRow] {
        guard let table = parseTable(csvString),
              let tsIdx = findColumn(in: table.header, keywords: ["timestamp", "time", "date"]),
              let rateIdx = findColumn(in: table.header, keywords: [
                  "basal rate (u/hr)", "rate (u/hr)", "rate(u/hr)", "basal rate",
                  "u/hr", "units/hr", "rate"
              ])
        else { return [] }

        let durIdx = findColumn(in: table.header, keywords: ["duration"])
        let durHeader = durIdx.flatMap { table.header[$0].lowercased() } ?? ""
        let durationInMinutes = durHeader.contains("min")
        let durationInHours = durHeader.contains("hr") && !durHeader.contains("u/")

        var rows: [BasalRow] = []
        for cols in table.rows {
            guard cols.count > max(tsIdx, rateIdx),
                  let ts = parseFlexibleDate(cols[tsIdx]),
                  let rate = Double(cols[rateIdx]),
                  rate >= 0 else { continue }
            var durSec: Double = 0
            if let di = durIdx, cols.count > di, let raw = Double(cols[di]) {
                if durationInHours { durSec = raw * 3600 }
                else if durationInMinutes { durSec = raw * 60 }
                else { durSec = raw }
            }
            rows.append(BasalRow(timestamp: ts, rate: rate, durationSeconds: durSec))
        }
        return rows
    }

    // MARK: - Insulin summary

    static func parseInsulinSummary(from csvString: String) -> [InsulinDayRow] {
        guard let table = parseTable(csvString),
              let tsIdx = findColumn(in: table.header, keywords: ["timestamp", "date"])
        else { return [] }
        let bolusIdx = findColumn(in: table.header, keywords: ["total bolus", "bolus"])
        let totalIdx = findColumn(in: table.header, keywords: ["total insulin", "total"])
        let basalIdx = findColumn(in: table.header, keywords: ["total basal", "basal"])
        guard let bi = bolusIdx, let ti = totalIdx, let ba = basalIdx else { return [] }

        var rows: [InsulinDayRow] = []
        for cols in table.rows {
            guard cols.count > max(max(tsIdx, bi), max(ti, ba)),
                  let ts = parseFlexibleDate(cols[tsIdx]),
                  let bolus = Double(cols[bi]),
                  let total = Double(cols[ti]),
                  let basal = Double(cols[ba]) else { continue }
            rows.append(InsulinDayRow(timestamp: ts, totalBolus: bolus, totalInsulin: total, totalBasal: basal))
        }
        return rows
    }

    // MARK: - Adaptive CSV helpers

    private struct Table {
        let header: [String]
        let rows: [[String]]
    }

    /// Splits a CSV into a header row + data rows. Glooko prepends a metadata
    /// row like `Name:Anthony Loya,Date Range:2026-04-09 - 2026-04-22`, which
    /// contains the word "Date" but is NOT the column header. We reject that
    /// row by requiring the first cell of a candidate header row to be an
    /// exact timestamp keyword (e.g. exactly "Timestamp"), not just to
    /// contain one.
    private static func parseTable(_ csv: String) -> Table? {
        let lines = csv.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let tsFirstCellKeywords: Set<String> = [
            "timestamp", "time", "date", "datetime", "date/time", "date time"
        ]
        // Strip UTF-8 BOM + whitespace, which Glooko might prepend to a CSV.
        let cleanupChars = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\u{FEFF}"))
        var headerIdx = -1
        for (i, line) in lines.enumerated() {
            let parts = splitCSVLine(line)
            guard let first = parts.first?.lowercased()
                .trimmingCharacters(in: cleanupChars),
                  !first.contains(":") else { continue }
            if tsFirstCellKeywords.contains(first) {
                headerIdx = i
                break
            }
        }
        guard headerIdx >= 0 else { return nil }

        let header = splitCSVLine(lines[headerIdx])
        let rows: [[String]] = lines.dropFirst(headerIdx + 1).map { splitCSVLine($0) }
        return Table(header: header, rows: rows)
    }

    /// Quote-aware CSV line splitter. Handles `"value, with commas"` and
    /// doubled-quote escapes (`""`).
    private static func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" {
                let next = line.index(after: i)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    i = next
                } else {
                    inQuotes.toggle()
                }
            } else if c == ",", !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(c)
            }
            i = line.index(after: i)
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    /// Finds a column whose header matches any keyword. Keywords are tried in
    /// order — more specific phrases first so exact matches beat partial ones.
    private static func findColumn(in header: [String], keywords: [String]) -> Int? {
        let lowered = header.map { $0.lowercased() }
        for keyword in keywords {
            let k = keyword.lowercased()
            if let idx = lowered.firstIndex(of: k) { return idx }
            if let idx = lowered.firstIndex(where: { $0.contains(k) }) { return idx }
        }
        return nil
    }

    /// Try a handful of date formats Glooko's CSVs are known to use.
    private static func parseFlexibleDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        for formatter in Self.dateFormatters {
            if let d = formatter.date(from: s) { return d }
        }
        // ISO 8601 fallback (with and without fractional seconds).
        if let d = Self.iso8601Basic.date(from: s) { return d }
        if let d = Self.iso8601Fractional.date(from: s) { return d }
        return nil
    }

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy hh:mm a",
            "M/d/yyyy HH:mm",
            "M/d/yyyy h:mm a",
            "M/d/yyyy",
            "yyyy/MM/dd HH:mm:ss",
        ]
        return formats.map { fmt in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            // Glooko timestamps are local-time unless they carry an explicit
            // offset, so default to the current zone rather than UTC.
            df.timeZone = .current
            return df
        }
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Trend Arrow from sequential readings

    static func inferTrend(current: Int, previous: Int?) -> TrendArrow {
        guard let prev = previous else { return .flat }
        let delta = current - prev
        if delta > 15 { return .risingFast }
        if delta > 5 { return .rising }
        if delta < -15 { return .fallingFast }
        if delta < -5 { return .falling }
        return .flat
    }
}
