import Foundation
import SwiftData

/// Insulin dose record backfilled from Glooko's bolus/basal CSVs. Bolus rows
/// are discrete events (a single injection/delivery), basal rows are segments
/// describing a rate in effect starting at `timestamp` for `durationSeconds`.
@Model
final class InsulinEntry {
    var timestamp: Date
    /// Units delivered for bolus, or units/hr for basal.
    var units: Double
    var kindRaw: String
    /// For basal segments: duration the rate was in effect, in seconds. 0 for bolus.
    var durationSeconds: Double
    /// Carbs entered with the bolus, in grams. 0 if unknown / basal.
    var carbs: Double
    /// Source tag, e.g. "glooko", "manual".
    var sourceRaw: String

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .bolus }
        set { kindRaw = newValue.rawValue }
    }

    enum Kind: String, Codable, CaseIterable {
        case bolus
        case basal
        case correction
    }

    init(
        timestamp: Date,
        units: Double,
        kind: Kind = .bolus,
        durationSeconds: Double = 0,
        carbs: Double = 0,
        source: String = "glooko"
    ) {
        self.timestamp = timestamp
        self.units = units
        self.kindRaw = kind.rawValue
        self.durationSeconds = durationSeconds
        self.carbs = carbs
        self.sourceRaw = source
    }
}
