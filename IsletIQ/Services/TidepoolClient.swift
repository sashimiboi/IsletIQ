import Foundation

/// Tidepool API client for diabetes device data.
/// Tidepool is an open platform that aggregates data from CGMs, pumps, and BGMs.
actor TidepoolClient {
    enum Environment: String, CaseIterable {
        case production = "production"
        case integration = "integration"

        var baseURL: String {
            switch self {
            case .production: return "https://api.tidepool.org"
            case .integration: return "https://int-api.tidepool.org"
            }
        }
    }

    struct UserData: Codable {
        let userid: String?
        let username: String?
    }

    struct DeviceDatum: Codable {
        let id: String?
        let type: String?          // "cbg", "smbg", "bolus", "basal", "wizard", "food"
        let time: String?
        let deviceId: String?
        let uploadId: String?

        // CGM/BGM fields
        let value: Double?         // mmol/L
        let units: String?         // "mmol/L" or "mg/dL"

        // Bolus fields
        let subType: String?       // "normal", "square", "dual/square"
        let normal: Double?        // units delivered
        let extended: Double?

        // Basal fields
        let rate: Double?          // u/hr
        let duration: Int?         // ms
        let deliveryType: String?  // "scheduled", "temp", "suspend"

        // Food/wizard
        let carbInput: Double?
        let insulinCarbRatio: Double?
        let insulinSensitivity: Double?
        let bgTarget: [String: Double]?

        var mgDl: Int {
            guard let v = value else { return 0 }
            if units == "mmol/L" { return Int(v * 18.0182) }
            return Int(v)
        }

        var timestamp: Date? {
            guard let t = time else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: t) ?? ISO8601DateFormatter().date(from: t)
        }
    }

    enum TidepoolError: LocalizedError {
        case invalidCredentials
        case networkError(String)
        case noData

        var errorDescription: String? {
            switch self {
            case .invalidCredentials: return "Invalid Tidepool credentials"
            case .networkError(let msg): return "Network error: \(msg)"
            case .noData: return "No data from Tidepool"
            }
        }
    }

    private let environment: Environment
    private var authToken: String?
    private var userId: String?

    init(environment: Environment = .production) {
        self.environment = environment
    }

    // MARK: - Auth

    /// Login with email/password. Tidepool uses HTTP Basic Auth for login, returns a session token.
    func login(email: String, password: String) async throws -> String {
        let url = URL(string: "\(environment.baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

        // Basic Auth header
        let credentials = "\(email):\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TidepoolError.networkError("Invalid response")
        }
        guard http.statusCode == 200 else {
            throw TidepoolError.invalidCredentials
        }

        // Token comes in x-tidepool-session-token header
        guard let token = http.value(forHTTPHeaderField: "x-tidepool-session-token") else {
            throw TidepoolError.networkError("Missing session token in response")
        }

        // User ID from response body
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        self.userId = json?["userid"] as? String
        self.authToken = token
        return token
    }

    // MARK: - Data

    /// Fetch device data for the logged-in user. Types: cbg, smbg, bolus, basal, wizard, food
    func fetchData(type: String? = nil, startDate: Date? = nil, endDate: Date? = nil) async throws -> [DeviceDatum] {
        guard let token = authToken, let uid = userId else {
            throw TidepoolError.invalidCredentials
        }

        var query: [String: String] = [:]
        if let type { query["type"] = type }

        let isoFormatter = ISO8601DateFormatter()
        if let start = startDate { query["startDate"] = isoFormatter.string(from: start) }
        if let end = endDate { query["endDate"] = isoFormatter.string(from: end) }

        var components = URLComponents(string: "\(environment.baseURL)/data/\(uid)")!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue(token, forHTTPHeaderField: "x-tidepool-session-token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TidepoolError.networkError("Invalid response")
        }
        guard http.statusCode == 200 else {
            throw TidepoolError.networkError("Status \(http.statusCode)")
        }

        return try JSONDecoder().decode([DeviceDatum].self, from: data)
    }

    /// Fetch CGM readings (continuous blood glucose).
    func fetchCGM(startDate: Date? = nil) async throws -> [DeviceDatum] {
        let start = startDate ?? Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        return try await fetchData(type: "cbg", startDate: start)
    }

    /// Fetch bolus data.
    func fetchBoluses(startDate: Date? = nil) async throws -> [DeviceDatum] {
        let start = startDate ?? Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        return try await fetchData(type: "bolus", startDate: start)
    }

    /// Fetch basal data.
    func fetchBasal(startDate: Date? = nil) async throws -> [DeviceDatum] {
        let start = startDate ?? Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        return try await fetchData(type: "basal", startDate: start)
    }
}
