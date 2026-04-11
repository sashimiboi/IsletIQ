import Foundation

struct MockData {

    // Cache parsed data so we don't re-parse CSV on every access
    private static var _cachedReadings: [GlucoseReading]?
    private static var _cachedBolus: [GlookoImporter.BolusRow]?

    // MARK: - Load real Glooko data

    static func glucoseReadings() -> [GlucoseReading] {
        if let cached = _cachedReadings { return cached }
        guard let url = Bundle.main.url(forResource: "cgm_data", withExtension: "csv"),
              let csv = try? String(contentsOf: url, encoding: .utf8)
        else {
            return fallbackReadings()
        }

        let cgmRows = GlookoImporter.parseCGM(from: csv)
        guard !cgmRows.isEmpty else { return fallbackReadings() }

        // Take last 7 days of data to keep it manageable
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = cgmRows.filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        var readings: [GlucoseReading] = []
        for (i, row) in recent.enumerated() {
            let prev = i > 0 ? recent[i - 1].value : nil
            let trend = GlookoImporter.inferTrend(current: row.value, previous: prev)
            readings.append(GlucoseReading(
                value: row.value,
                timestamp: row.timestamp,
                trendArrow: trend,
                source: .cgm
            ))
        }
        _cachedReadings = readings
        return readings
    }

    static func bolusData() -> [GlookoImporter.BolusRow] {
        if let cached = _cachedBolus { return cached }
        guard let url = Bundle.main.url(forResource: "bolus_data", withExtension: "csv"),
              let csv = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        let data = GlookoImporter.parseBolus(from: csv)
        _cachedBolus = data
        return data
    }

    static func insulinSummary() -> [GlookoImporter.InsulinDayRow] {
        guard let url = Bundle.main.url(forResource: "insulin_data", withExtension: "csv"),
              let csv = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return GlookoImporter.parseInsulinSummary(from: csv)
    }

    // Fallback if CSVs aren't bundled
    private static func fallbackReadings() -> [GlucoseReading] {
        let data: [(Int, Double, TrendArrow)] = [
            (112, 0.08, .flat), (118, 0.17, .rising), (131, 0.5, .risingFast),
            (142, 0.75, .rising), (138, 1.5, .falling), (118, 2.5, .falling),
            (105, 3.5, .flat), (95, 4.5, .flat), (88, 5.5, .falling),
            (115, 6.5, .rising), (135, 7.0, .rising), (125, 9.0, .falling),
            (110, 10.0, .flat), (98, 12.0, .flat), (90, 16.0, .flat),
        ]
        return data.map { val, hrs, trend in
            GlucoseReading(value: val, timestamp: Date().addingTimeInterval(-hrs * 3600), trendArrow: trend)
        }
    }

    // MARK: - Pump mock data (from your real Omnipod 5 settings)

    static var pumpBattery: Int { 72 }
    static var reservoirUnits: Double { 124.5 }
    static var reservoirMax: Double { 200.0 }
    static var activeBasalRate: Double { 0.5 }
    static var carbRatio: Double { 13.0 }

    static var iob: Double {
        // Estimate from recent boluses — just mock for now
        let boluses = bolusData()
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        let recent = boluses.filter { $0.timestamp >= twoHoursAgo }
        return recent.isEmpty ? 1.2 : recent.reduce(0.0) { $0 + $1.insulinDelivered * 0.4 }
    }

    static var cob: Int {
        let boluses = bolusData()
        let threeHoursAgo = Date().addingTimeInterval(-3 * 3600)
        let recent = boluses.filter { $0.timestamp >= threeHoursAgo }
        return recent.isEmpty ? 0 : recent.reduce(0) { $0 + $1.carbs } / 2
    }

    static var lastBolus: Double {
        bolusData().first?.insulinDelivered ?? 4.6
    }

    static var lastBolusTime: Date {
        bolusData().first?.timestamp ?? Date().addingTimeInterval(-1.5 * 3600)
    }

    static let pumpModel: String = "Omnipod 5"
    static let cgmModel: String = "Dexcom G7"
    static let sensorDaysRemaining: Int = 4
}
