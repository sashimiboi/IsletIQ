import Foundation

struct GlookoImporter {

    // MARK: - CGM Data

    struct CGMRow {
        let timestamp: Date
        let value: Int
    }

    static func parseCGM(from csvString: String) -> [CGMRow] {
        let lines = csvString.components(separatedBy: .newlines)
        guard lines.count > 2 else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var rows: [CGMRow] = []
        // Skip line 0 (header metadata) and line 1 (column headers)
        for i in 2..<lines.count {
            let cols = lines[i].components(separatedBy: ",")
            guard cols.count >= 2,
                  let date = formatter.date(from: cols[0].trimmingCharacters(in: .whitespaces)),
                  let val = Double(cols[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            rows.append(CGMRow(timestamp: date, value: Int(val)))
        }
        return rows
    }

    // MARK: - Bolus Data

    struct BolusRow {
        let timestamp: Date
        let carbs: Int
        let insulinDelivered: Double
        let carbRatio: Double
    }

    static func parseBolus(from csvString: String) -> [BolusRow] {
        let lines = csvString.components(separatedBy: .newlines)
        guard lines.count > 2 else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var rows: [BolusRow] = []
        for i in 2..<lines.count {
            let cols = lines[i].components(separatedBy: ",")
            guard cols.count >= 6,
                  let date = formatter.date(from: cols[0].trimmingCharacters(in: .whitespaces)),
                  let carbs = Double(cols[3].trimmingCharacters(in: .whitespaces)),
                  let ratio = Double(cols[4].trimmingCharacters(in: .whitespaces)),
                  let insulin = Double(cols[5].trimmingCharacters(in: .whitespaces))
            else { continue }
            rows.append(BolusRow(timestamp: date, carbs: Int(carbs), insulinDelivered: insulin, carbRatio: ratio))
        }
        return rows
    }

    // MARK: - Daily Insulin Summary

    struct InsulinDayRow {
        let timestamp: Date
        let totalBolus: Double
        let totalInsulin: Double
        let totalBasal: Double
    }

    static func parseInsulinSummary(from csvString: String) -> [InsulinDayRow] {
        let lines = csvString.components(separatedBy: .newlines)
        guard lines.count > 2 else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var rows: [InsulinDayRow] = []
        for i in 2..<lines.count {
            let cols = lines[i].components(separatedBy: ",")
            guard cols.count >= 4,
                  let date = formatter.date(from: cols[0].trimmingCharacters(in: .whitespaces)),
                  let bolus = Double(cols[1].trimmingCharacters(in: .whitespaces)),
                  let total = Double(cols[2].trimmingCharacters(in: .whitespaces)),
                  let basal = Double(cols[3].trimmingCharacters(in: .whitespaces))
            else { continue }
            rows.append(InsulinDayRow(timestamp: date, totalBolus: bolus, totalInsulin: total, totalBasal: basal))
        }
        return rows
    }

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
