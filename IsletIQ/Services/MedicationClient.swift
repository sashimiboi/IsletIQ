import Foundation

actor MedicationClient {
    private let baseURL: String

    init(baseURL: String = APIConfig.baseURLSync) {
        self.baseURL = baseURL
    }

    func fetchMedications() async -> [Medication] {
        guard let url = URL(string: "\(baseURL)/api/medications") else { return [] }
        guard APIConfig.authToken != nil else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        APIConfig.applyAuth(to: &request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 { return [] }
            struct Wrapper: Codable { let medications: [Medication] }
            let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
            return wrapper.medications
        } catch {
            print("MedicationClient fetch error: \(error)")
            return []
        }
    }

    func fetchTodaySchedule() async -> [TodayMedication] {
        guard let url = URL(string: "\(baseURL)/api/medications/today") else { return [] }
        guard APIConfig.authToken != nil else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        APIConfig.applyAuth(to: &request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 { return [] }
            struct Wrapper: Codable { let medications: [TodayMedication] }
            let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
            return wrapper.medications
        } catch {
            print("MedicationClient today error: \(error)")
            return []
        }
    }

    func fetchHistory(days: Int = 14) async -> MedicationHistoryResult {
        guard let url = URL(string: "\(baseURL)/api/medications/history?days=\(days)") else {
            return .init(days: [], errorMessage: "Invalid URL")
        }
        guard APIConfig.authToken != nil else {
            return .init(days: [], errorMessage: "Not signed in")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        APIConfig.applyAuth(to: &request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                await MainActor.run { AuthManager.handleUnauthorized() }
                return .init(days: [], errorMessage: "Signed out")
            }
            if status == 404 {
                print("MedicationClient history: 404. Restart FastAPI to pick up /api/medications/history")
                return .init(days: [], errorMessage: "Endpoint missing. Restart the backend.")
            }
            if status / 100 != 2 {
                let body = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
                print("MedicationClient history HTTP \(status): \(body)")
                return .init(days: [], errorMessage: "HTTP \(status)")
            }
            struct Wrapper: Codable { let days: [MedicationHistoryDay] }
            let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
            return .init(days: wrapper.days, errorMessage: nil)
        } catch let error as URLError where error.code == .cancelled {
            // View transition cancelled the task; not a real failure.
            return .init(days: [], errorMessage: nil)
        } catch {
            print("MedicationClient history error: \(error)")
            return .init(days: [], errorMessage: "Network error")
        }
    }

    func createMedication(name: String, dosage: String, category: String, frequency: String, scheduleTimes: [String], notes: String = "", intervalDays: Int = 1, dueWeekday: Int? = nil, dueDayOfMonth: Int? = nil) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/medications") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        var body: [String: Any] = [
            "name": name, "dosage": dosage, "category": category,
            "frequency": frequency, "schedule_times": scheduleTimes, "notes": notes,
            "interval_days": intervalDays,
        ]
        if let dueWeekday { body["due_weekday"] = dueWeekday }
        if let dueDayOfMonth { body["due_day_of_month"] = dueDayOfMonth }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }

    func updateMedication(id: Int, name: String? = nil, dosage: String? = nil, category: String? = nil, frequency: String? = nil, scheduleTimes: [String]? = nil, notes: String? = nil, isActive: Bool? = nil, intervalDays: Int? = nil, dueWeekday: Int? = nil, dueDayOfMonth: Int? = nil) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/medications/\(id)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let dosage { body["dosage"] = dosage }
        if let category { body["category"] = category }
        if let frequency { body["frequency"] = frequency }
        if let scheduleTimes { body["schedule_times"] = scheduleTimes }
        if let notes { body["notes"] = notes }
        if let isActive { body["is_active"] = isActive }
        if let intervalDays { body["interval_days"] = intervalDays }
        if let dueWeekday { body["due_weekday"] = dueWeekday }
        if let dueDayOfMonth { body["due_day_of_month"] = dueDayOfMonth }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }

    func deleteMedication(id: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/medications/\(id)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        APIConfig.applyAuth(to: &request)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }

    func unlogDose(medicationId: Int, scheduledTime: String?) async -> Bool {
        var components = URLComponents(string: "\(baseURL)/api/medications/\(medicationId)/doses")
        if let scheduledTime {
            components?.queryItems = [URLQueryItem(name: "scheduled_time", value: scheduledTime)]
        }
        guard let url = components?.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        APIConfig.applyAuth(to: &request)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }

    func logDose(medicationId: Int, scheduledTime: String?, status: String = "taken") async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/medications/\(medicationId)/doses") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        var body: [String: Any] = ["status": status]
        if let scheduledTime { body["scheduled_time"] = scheduledTime }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }
}
