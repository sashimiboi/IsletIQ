import Foundation

struct PatientRosterEntry: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String?
    let email: String
    let cohort: String?
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

    var cohortLabel: String {
        switch cohort {
        case "t1d":  return "T1D"
        case "t2d":  return "T2D"
        case "glp1": return "GLP-1"
        case "gdm":  return "GDM"
        default:     return cohort?.uppercased() ?? "T1D"
        }
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

// MARK: - Patient detail (provider per-patient pane)

struct PatientDetail: Decodable {
    let patient: PatientIdentity
    let cgm: PatientCGM
    let medications: [PatientMedication]
    let supplies: [PatientSupply]
    let sleep: PatientSleep?
    let nutrition: PatientNutrition?
}

struct PatientIdentity: Decodable {
    let id: Int
    let name: String?
    let email: String
    let cohort: String
    let linked_at: String?

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        return email
    }
}

struct PatientCGM: Decodable {
    let series_14d: [CGMPoint]
    let tir_pct: Double?
    let hypo_events_14d: Int
    let avg_mg_dl_14d: Int?
    let reading_count_14d: Int
    let last_reading_at: String?
}

struct CGMPoint: Decodable, Identifiable {
    let timestamp: String
    let mg_dl: Int

    var id: String { timestamp }

    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: timestamp) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: timestamp)
    }
}

struct PatientMedication: Decodable, Identifiable {
    let id: Int
    let name: String
    let dosage: String
    let category: String
    let frequency: String
    let schedule_times: [String]
    let taken_7d: Int
    let expected_7d: Int
    let adherence_pct_7d: Double?
}

struct PatientSupply: Decodable, Identifiable {
    let id: Int
    let name: String
    let category: String
    let quantity: Int
    let usage_rate_days: Double
    let alert_days_before: Int
    let expiration_date: String?
    let projected_days_remaining: Double?
    let is_low: Bool
}

struct PatientSleep: Decodable {
    let last_7d: [SleepNight]
    let avg_hours_7d: Double?
}

struct SleepNight: Decodable, Identifiable {
    let date: String
    let total_hours: Double?
    let deep_minutes: Int?
    let rem_minutes: Int?
    let core_minutes: Int?
    let awake_minutes: Int?
    let quality: String?
    let bedtime: String?
    let wake_time: String?

    var id: String { date }

    var qualityLabel: String {
        switch quality {
        case "good":  return "Good"
        case "fair":  return "Fair"
        case "poor":  return "Poor"
        default:      return quality?.capitalized ?? "—"
        }
    }
}

struct PatientNutrition: Decodable {
    let meals_7d: [MealRecord]
    let avg_carbs_per_day_7d: Double?
    let avg_calories_per_day_7d: Double?
}

struct MealRecord: Decodable, Identifiable {
    let date: String
    let name: String
    let carbs_g: Int
    let calories: Int

    var id: String { "\(date)-\(name)" }
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

    func linkPatient(email: String) async -> (success: Bool, error: String?) {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/provider/patients/link") else {
            return (false, "Bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["patient_email": email])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 { AuthManager.handleUnauthorized(); return (false, "Session expired") }
            if status / 100 != 2 {
                let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                return (false, detail ?? "Couldn't link patient (\(status))")
            }
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func unlinkPatient(id: Int) async -> Bool {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/provider/patients/\(id)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        APIConfig.applyAuth(to: &request)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }

    func fetchPatientDetail(_ patientId: Int) async -> PatientDetail? {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/provider/patients/\(patientId)/detail") else { return nil }
        var request = URLRequest(url: url)
        APIConfig.applyAuth(to: &request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 { AuthManager.handleUnauthorized(); return nil }
                if http.statusCode != 200 { return nil }
            }
            return try JSONDecoder().decode(PatientDetail.self, from: data)
        } catch {
            return nil
        }
    }
}
