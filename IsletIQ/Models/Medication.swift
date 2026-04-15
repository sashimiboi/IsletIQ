import Foundation

struct Medication: Identifiable, Codable {
    let id: Int
    var name: String
    var dosage: String
    var category: String
    var frequency: String
    var scheduleTimes: [String]
    var notes: String
    var isActive: Bool
    var intervalDays: Int = 1
    var dueWeekday: Int? = nil
    var dueDayOfMonth: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, dosage, category, frequency, notes
        case scheduleTimes = "schedule_times"
        case isActive = "is_active"
        case intervalDays = "interval_days"
        case dueWeekday = "due_weekday"
        case dueDayOfMonth = "due_day_of_month"
    }

    var categoryIcon: String {
        switch category {
        case "insulin": "drop.fill"
        case "adjunct": "pills.fill"
        case "statin": "heart.fill"
        case "thyroid": "bolt.heart.fill"
        case "vitamin": "leaf.fill"
        case "supplement": "capsule.fill"
        default: "pills.fill"
        }
    }

    var frequencyLabel: String {
        switch frequency {
        case "daily": "Daily"
        case "twice_daily": "Twice daily"
        case "three_times": "3x daily"
        case "weekly": "Weekly"
        case "biweekly": "Every 2 weeks"
        case "monthly": "Monthly"
        case "as_needed": "As needed"
        default: frequency.capitalized
        }
    }

    var cadenceIcon: String {
        switch intervalDays {
        case 0: "hand.tap.fill"
        case 1: "sun.max.fill"
        case 7: "calendar.badge.clock"
        case 14: "calendar"
        case 15...: "calendar.circle.fill"
        default: "clock.fill"
        }
    }

    var cadenceLabel: String {
        if let dom = dueDayOfMonth {
            return "\(ordinal(dom)) of month"
        }
        if let wday = dueWeekday {
            return Self.weekdayNames[wday % 7] + "s"
        }
        switch intervalDays {
        case 0: return "As needed"
        case 1: return "Daily"
        case 7: return "Weekly"
        case 14: return "Every 2 weeks"
        case 28, 30, 31: return "Monthly"
        default: return "Every \(intervalDays) days"
        }
    }

    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        let mod100 = n % 100
        let mod10 = n % 10
        if (11...13).contains(mod100) { suffix = "th" }
        else if mod10 == 1 { suffix = "st" }
        else if mod10 == 2 { suffix = "nd" }
        else if mod10 == 3 { suffix = "rd" }
        else { suffix = "th" }
        return "\(n)\(suffix)"
    }
}

enum MedicationTimeFormatter {
    private static let inputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f
    }()

    /// Convert "HH:mm" (24h) to "h:mm AM/PM" for display.
    static func display(_ militaryTime: String) -> String {
        guard let date = inputFormatter.date(from: militaryTime) else { return militaryTime }
        return displayFormatter.string(from: date)
    }
}

struct TodayMedication: Identifiable, Codable {
    let id: Int
    let name: String
    let dosage: String
    let category: String
    let scheduleTimes: [String]
    let doses: [TodayDose]
    let intervalDays: Int
    let dueWeekday: Int?
    let dueDayOfMonth: Int?
    let lastTakenDate: String?
    let nextDueDate: String?
    let daysOverdue: Int

    enum CodingKeys: String, CodingKey {
        case id, name, dosage, category, doses
        case scheduleTimes = "schedule_times"
        case intervalDays = "interval_days"
        case dueWeekday = "due_weekday"
        case dueDayOfMonth = "due_day_of_month"
        case lastTakenDate = "last_taken_date"
        case nextDueDate = "next_due_date"
        case daysOverdue = "days_overdue"
    }

    var totalSlots: Int { scheduleTimes.count }
    var takenCount: Int { doses.filter { $0.status == "taken" }.count }
    var allTaken: Bool { takenCount >= totalSlots }
    var isDaily: Bool { intervalDays <= 1 }
    var isOverdue: Bool { daysOverdue > 0 }

    var cadenceLabel: String {
        if let dom = dueDayOfMonth {
            let n = dom
            let mod100 = n % 100, mod10 = n % 10
            let suffix = (11...13).contains(mod100) ? "th"
                : mod10 == 1 ? "st"
                : mod10 == 2 ? "nd"
                : mod10 == 3 ? "rd" : "th"
            return "\(n)\(suffix) of month"
        }
        if let wday = dueWeekday {
            return Medication.weekdayNames[wday % 7] + "s"
        }
        switch intervalDays {
        case 0: return "As needed"
        case 1: return "Daily"
        case 7: return "Weekly"
        case 14: return "Every 2 weeks"
        case 28, 30, 31: return "Monthly"
        default: return "Every \(intervalDays) days"
        }
    }

    func isDoseTaken(at time: String) -> Bool {
        doses.contains { $0.scheduledTime == time && $0.status == "taken" }
    }
}

struct MedicationHistoryEntry: Codable, Hashable {
    let medicationId: Int
    let name: String
    let category: String
    let taken: Int
    let expected: Int

    enum CodingKeys: String, CodingKey {
        case medicationId = "medication_id"
        case name, category, taken, expected
    }

    var missed: Int { max(0, expected - taken) }
}

struct MedicationHistoryDay: Codable, Identifiable {
    let date: String
    let entries: [MedicationHistoryEntry]

    var id: String { date }
}

struct MedicationHistoryResult {
    let days: [MedicationHistoryDay]
    let errorMessage: String?
}

struct TodayDose: Codable {
    let scheduledTime: String?
    let status: String?
    let takenAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case scheduledTime = "scheduled_time"
        case takenAt = "taken_at"
    }
}
