import Foundation

/// Nightscout REST API client.
/// Nightscout is an open-source CGM data platform that many T1D users self-host.
/// It bridges data from Dexcom, Libre, Medtronic, and others into a single API.
actor NightscoutClient {
    private let baseURL: String
    private let apiSecret: String?

    struct Entry: Codable {
        let _id: String?
        let sgv: Int?           // sensor glucose value (mg/dL)
        let date: Double?       // epoch ms
        let dateString: String?
        let trend: Int?         // 1-9 trend arrow
        let direction: String?  // "Flat", "SingleUp", etc.
        let device: String?
        let type: String?       // "sgv", "mbg", "cal"

        var mgDl: Int { sgv ?? 0 }
        var timestamp: Date? {
            guard let d = date else { return nil }
            return Date(timeIntervalSince1970: d / 1000.0)
        }

        var trendArrow: String { direction ?? "Flat" }
    }

    struct Treatment: Codable {
        let _id: String?
        let eventType: String?   // "Meal Bolus", "Correction Bolus", "Temp Basal", "Carb Correction"
        let created_at: String?
        let insulin: Double?
        let carbs: Double?
        let notes: String?
    }

    struct Profile: Codable {
        let defaultProfile: String?
        let store: [String: ProfileStore]?
    }

    struct ProfileStore: Codable {
        let dia: Double?         // duration of insulin action
        let carbratio: [TimeValue]?
        let sens: [TimeValue]?   // ISF
        let basal: [TimeValue]?
        let target_low: [TimeValue]?
        let target_high: [TimeValue]?
    }

    struct TimeValue: Codable {
        let time: String?
        let value: Double?
        let timeAsSeconds: Int?
    }

    enum NightscoutError: LocalizedError {
        case invalidURL
        case unauthorized
        case networkError(String)
        case noData

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Nightscout URL"
            case .unauthorized: return "Invalid API secret"
            case .networkError(let msg): return "Network error: \(msg)"
            case .noData: return "No data from Nightscout"
            }
        }
    }

    /// Initialize with Nightscout site URL and optional API secret.
    /// URL should be like "https://my-nightscout.herokuapp.com" or "https://ns.example.com"
    init(siteURL: String, apiSecret: String? = nil) {
        self.baseURL = siteURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiSecret = apiSecret
    }

    private func makeRequest(_ path: String, query: [String: String] = [:]) -> URLRequest? {
        var components = URLComponents(string: "\(baseURL)/api/v1\(path)")
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let secret = apiSecret {
            // Nightscout accepts API_SECRET as SHA1 hash in header
            request.setValue(secret, forHTTPHeaderField: "api-secret")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - Status

    /// Check if the Nightscout instance is reachable and auth works.
    func verifyConnection() async throws -> Bool {
        guard let request = makeRequest("/status.json") else {
            throw NightscoutError.invalidURL
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NightscoutError.networkError("Invalid response")
        }
        if http.statusCode == 401 { throw NightscoutError.unauthorized }
        return http.statusCode == 200
    }

    // MARK: - Entries (CGM readings)

    /// Fetch recent SGV entries. Default last 288 (24 hours at 5-min intervals).
    func fetchEntries(count: Int = 288) async throws -> [Entry] {
        guard let request = makeRequest("/entries/sgv.json", query: ["count": "\(count)"]) else {
            throw NightscoutError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NightscoutError.networkError("Invalid response")
        }
        if http.statusCode == 401 { throw NightscoutError.unauthorized }
        guard http.statusCode == 200 else {
            throw NightscoutError.networkError("Status \(http.statusCode)")
        }
        return try JSONDecoder().decode([Entry].self, from: data)
    }

    // MARK: - Treatments (boluses, carbs, temp basals)

    /// Fetch recent treatments.
    func fetchTreatments(count: Int = 50) async throws -> [Treatment] {
        guard let request = makeRequest("/treatments.json", query: ["count": "\(count)"]) else {
            throw NightscoutError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NightscoutError.networkError("Invalid response")
        }
        if http.statusCode == 401 { throw NightscoutError.unauthorized }
        return try JSONDecoder().decode([Treatment].self, from: data)
    }

    // MARK: - Profile (basal rates, I:C, ISF)

    /// Fetch the user's treatment profile.
    func fetchProfile() async throws -> [Profile] {
        guard let request = makeRequest("/profile.json") else {
            throw NightscoutError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NightscoutError.networkError("Invalid response")
        }
        if http.statusCode == 401 { throw NightscoutError.unauthorized }
        return try JSONDecoder().decode([Profile].self, from: data)
    }
}
