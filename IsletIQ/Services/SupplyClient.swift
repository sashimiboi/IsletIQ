import Foundation

actor SupplyClient {
    private let baseURL: String

    init(baseURL: String = APIConfig.baseURLSync) {
        self.baseURL = baseURL
    }

    struct SupplyResponse: Codable {
        let id: Int
        let name: String
        let category: String
        let quantity: Int
        let usage_rate_days: Double
        let alert_days_before: Int
        let expiration_date: String?
        let insurance_refill_date: String?
        let notes: String?
        let days_remaining: Int
        let needs_alert: Bool
    }

    func fetchSupplies() async -> [SupplyResponse] {
        guard let url = URL(string: "\(baseURL)/api/supplies") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Wrapper: Codable { let supplies: [SupplyResponse] }
            let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
            return wrapper.supplies
        } catch {
            print("SupplyClient fetch error: \(error)")
            return []
        }
    }

    func createSupply(name: String, category: String, quantity: Int, usageRateDays: Double, notes: String = "") async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/supplies") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": name, "category": category, "quantity": quantity,
            "usage_rate_days": usageRateDays, "notes": notes
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    func useSupply(id: Int, count: Int = 1) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/supplies/\(id)/use?count=\(count)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    func setQuantity(id: Int, quantity: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/supplies/\(id)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["quantity": max(0, quantity)]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    func deleteSupply(id: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/supplies/\(id)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}
