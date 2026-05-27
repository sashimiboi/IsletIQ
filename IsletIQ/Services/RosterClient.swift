import Foundation

struct PatientRosterEntry: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String?
    let email: String
    let linked_at: String?
    let tir_pct: Double?
    let hypo_events_14d: Int
    let adherence_pct_7d: Double?
    let low_supplies: Int
    let last_reading_at: String?
    let priority: String

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        return email
    }

    var priorityBucket: PatientPriority {
        PatientPriority(rawValue: priority) ?? .ok
    }
}

enum PatientPriority: String, CaseIterable {
    case critical
    case watch
    case ok

    var label: String {
        switch self {
        case .critical: return "Critical"
        case .watch:    return "Watch"
        case .ok:       return "Stable"
        }
    }
}

struct RosterClient {
    func fetchRoster() async -> [PatientRosterEntry] {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/provider/roster") else { return [] }
        var request = URLRequest(url: url)
        APIConfig.applyAuth(to: &request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                AuthManager.handleUnauthorized()
                return []
            }
            struct Envelope: Decodable { let patients: [PatientRosterEntry] }
            return try JSONDecoder().decode(Envelope.self, from: data).patients
        } catch {
            return []
        }
    }
}
