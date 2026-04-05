import Foundation
import SwiftData

@Model
final class GlucoseReading {
    var value: Int
    var timestamp: Date
    var note: String
    var mealTag: MealTag
    var trendArrowRaw: String = TrendArrow.flat.rawValue
    var sourceRaw: String = ReadingSource.cgm.rawValue

    var trendArrow: TrendArrow {
        get { TrendArrow(rawValue: trendArrowRaw) ?? .flat }
        set { trendArrowRaw = newValue.rawValue }
    }

    var source: ReadingSource {
        get { ReadingSource(rawValue: sourceRaw) ?? .cgm }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        value: Int,
        timestamp: Date = .now,
        note: String = "",
        mealTag: MealTag = .none,
        trendArrow: TrendArrow = .flat,
        source: ReadingSource = .cgm
    ) {
        self.value = value
        self.timestamp = timestamp
        self.note = note
        self.mealTag = mealTag
        self.trendArrowRaw = trendArrow.rawValue
        self.sourceRaw = source.rawValue
    }

    var status: GlucoseStatus {
        if value < 70 { return .low }
        if value <= 140 { return .normal }
        if value <= 180 { return .elevated }
        return .high
    }
}

enum GlucoseStatus: String, Codable {
    case low, normal, elevated, high

    var label: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .low: "blue"
        case .normal: "green"
        case .elevated: "orange"
        case .high: "red"
        }
    }
}

enum MealTag: String, Codable, CaseIterable {
    case none = "None"
    case fasting = "Fasting"
    case beforeMeal = "Before Meal"
    case afterMeal = "After Meal"
    case bedtime = "Bedtime"
}

enum TrendArrow: String, Codable, CaseIterable {
    case risingFast = "Rising Fast"
    case rising = "Rising"
    case flat = "Flat"
    case falling = "Falling"
    case fallingFast = "Falling Fast"

    var symbol: String {
        switch self {
        case .risingFast: "arrow.up"
        case .rising: "arrow.up.right"
        case .flat: "arrow.right"
        case .falling: "arrow.down.right"
        case .fallingFast: "arrow.down"
        }
    }
}

enum ReadingSource: String, Codable {
    case cgm = "CGM"
    case manual = "Manual"
    case fingerstick = "Fingerstick"
}
