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
        // Dose log writes happen seconds before the next history fetch, so
        // a cached response would show stale taken/expected counts and
        // make the chart look frozen.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
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

    func createMedication(name: String, dosage: String, category: String, frequency: String, scheduleTimes: [String], notes: String = "", intervalDays: Int = 1, dueWeekday: Int? = nil, dueDayOfMonth: Int? = nil, quantity: Int = 0) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/medications") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        var body: [String: Any] = [
            "name": name, "dosage": dosage, "category": category,
            "frequency": frequency, "schedule_times": scheduleTimes, "notes": notes,
            "interval_days": intervalDays, "quantity": quantity,
        ]
        if let dueWeekday { body["due_weekday"] = dueWeekday }
        if let dueDayOfMonth { body["due_day_of_month"] = dueDayOfMonth }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }

    func updateMedication(id: Int, name: String? = nil, dosage: String? = nil, category: String? = nil, frequency: String? = nil, scheduleTimes: [String]? = nil, notes: String? = nil, isActive: Bool? = nil, intervalDays: Int? = nil, dueWeekday: Int? = nil, dueDayOfMonth: Int? = nil, quantity: Int? = nil) async -> Bool {
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
        if let quantity { body["quantity"] = quantity }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }

    func fetchDoseLog(medicationId: Int, date: Date? = nil, days: Int = 14) async -> [DoseRecord] {
        var components = URLComponents(string: "\(baseURL)/api/medications/\(medicationId)/doses")
        var items: [URLQueryItem] = []
        if let date { items.append(URLQueryItem(name: "date", value: Self.isoDateString(date))) }
        else { items.append(URLQueryItem(name: "days", value: "\(days)")) }
        components?.queryItems = items
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        APIConfig.applyAuth(to: &request)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct Wrapper: Codable { let doses: [DoseRecord] }
            return (try JSONDecoder().decode(Wrapper.self, from: data)).doses
        } catch { return [] }
    }

    func deleteDoseById(_ doseId: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/medications/doses/\(doseId)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        APIConfig.applyAuth(to: &request)
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

    func unlogDose(medicationId: Int, scheduledTime: String?, date: Date? = nil) async -> Bool {
        var components = URLComponents(string: "\(baseURL)/api/medications/\(medicationId)/doses")
        var items: [URLQueryItem] = []
        if let scheduledTime { items.append(URLQueryItem(name: "scheduled_time", value: scheduledTime)) }
        if let date { items.append(URLQueryItem(name: "date", value: Self.isoDateString(date))) }
        if !items.isEmpty { components?.queryItems = items }
        guard let url = components?.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        APIConfig.applyAuth(to: &request)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }

    func logDose(medicationId: Int, scheduledTime: String?, status: String = "taken", date: Date? = nil) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/medications/\(medicationId)/doses") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        var body: [String: Any] = ["status": status]
        if let scheduledTime { body["scheduled_time"] = scheduledTime }
        if let date { body["taken_at"] = Self.isoDateTimeString(date) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        } catch { return false }
    }

    private static func isoDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }

    private static func isoDateTimeString(_ d: Date) -> String {
        // For past dates, anchor the time to noon local so timezone slop
        // doesn't push the dose into the previous or next day on the server.
        let cal = Calendar.current
        let anchored = cal.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: anchored)
    }
}
