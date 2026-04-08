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

    enum CodingKeys: String, CodingKey {
        case id, name, dosage, category, frequency, notes
        case scheduleTimes = "schedule_times"
        case isActive = "is_active"
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
        case "as_needed": "As needed"
        default: frequency.capitalized
        }
    }
}

struct TodayMedication: Identifiable, Codable {
    let id: Int
    let name: String
    let dosage: String
    let category: String
    let scheduleTimes: [String]
    let doses: [TodayDose]

    enum CodingKeys: String, CodingKey {
        case id, name, dosage, category, doses
        case scheduleTimes = "schedule_times"
    }

    var totalSlots: Int { scheduleTimes.count }
    var takenCount: Int { doses.filter { $0.status == "taken" }.count }
    var allTaken: Bool { takenCount >= totalSlots }

    func isDoseTaken(at time: String) -> Bool {
        doses.contains { $0.scheduledTime == time && $0.status == "taken" }
    }
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
