import Foundation

actor DexcomShareClient {
    private let baseURL = "https://share2.dexcom.com/ShareWebServices/Services"
    private let applicationId = "d89443d2-327c-4a6f-89e5-496bbb0317db"

    private var sessionId: String?

    enum DexcomError: LocalizedError {
        case invalidCredentials
        case sessionExpired
        case networkError(String)
        case noData

        var errorDescription: String? {
            switch self {
            case .invalidCredentials: "Invalid Dexcom credentials"
            case .sessionExpired: "Session expired - please log in again"
            case .networkError(let msg): "Network error: \(msg)"
            case .noData: "No glucose data available"
            }
        }
    }

    struct ShareGlucoseReading: Codable {
        let WT: String?
        let ST: String?
        let DT: String?
        let Trend: String?
        let Value: Int?

        var timestamp: Date? {
            let dateString = WT ?? ST ?? DT
            guard let ds = dateString,
                  let start = ds.range(of: "("),
                  let end = ds.range(of: ")") else { return nil }
            let inner = String(ds[start.upperBound..<end.lowerBound])
            // Remove timezone offset like "-0500" or "+0000"
            let cleaned = inner.replacingOccurrences(of: #"[+-]\d{4}$"#, with: "", options: .regularExpression)
            guard let ms = Double(cleaned) else { return nil }
            return Date(timeIntervalSince1970: ms / 1000.0)
        }

        var trendArrow: TrendArrow {
            switch Trend ?? "Flat" {
            case "DoubleUp": .risingFast
            case "SingleUp": .risingFast
            case "FortyFiveUp": .rising
            case "Flat": .flat
            case "FortyFiveDown": .falling
            case "SingleDown": .fallingFast
            case "DoubleDown": .fallingFast
            default: .flat
            }
        }

        var safeValue: Int { Value ?? 0 }
    }

    // MARK: - Two-step Login

    func login(username: String, password: String) async throws -> String {
        // Step 1: Get account ID
        let accountId = try await authenticateAccount(username: username, password: password)

        // Step 2: Get session ID using account ID
        let session = try await loginById(accountId: accountId, password: password)
        self.sessionId = session
        return session
    }

    private func authenticateAccount(username: String, password: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/General/AuthenticatePublisherAccount") else {
            throw DexcomError.networkError("Invalid authenticate URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "accountName": username,
            "password": password,
            "applicationId": applicationId
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DexcomError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw DexcomError.invalidCredentials
        }

        guard let accountId = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) else {
            throw DexcomError.networkError("Invalid account response")
        }

        if accountId == "00000000-0000-0000-0000-000000000000" {
            throw DexcomError.invalidCredentials
        }

        return accountId
    }

    private func loginById(accountId: String, password: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/General/LoginPublisherAccountById") else {
            throw DexcomError.networkError("Invalid login URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "accountId": accountId,
            "password": password,
            "applicationId": applicationId
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DexcomError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw DexcomError.networkError("Login failed: status \(httpResponse.statusCode)")
        }

        guard let sessionId = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) else {
            throw DexcomError.networkError("Invalid session response")
        }

        if sessionId == "00000000-0000-0000-0000-000000000000" {
            throw DexcomError.networkError("Share not enabled - check Dexcom G7 app settings")
        }

        return sessionId
    }

    // MARK: - Fetch Readings

    func fetchLatestReadings(sessionId: String, minutes: Int = 1440, maxCount: Int = 288) async throws -> [ShareGlucoseReading] {
        guard let url = URL(string: "\(baseURL)/Publisher/ReadPublisherLatestGlucoseValues?sessionId=\(sessionId)&minutes=\(minutes)&maxCount=\(maxCount)") else {
            throw DexcomError.networkError("Invalid readings URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data()

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DexcomError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 500 {
            throw DexcomError.sessionExpired
        }

        guard httpResponse.statusCode == 200 else {
            throw DexcomError.networkError("Status \(httpResponse.statusCode)")
        }

        let readings = try JSONDecoder().decode([ShareGlucoseReading].self, from: data)
        print("Dexcom: \(readings.count) readings, latest: \(readings.first?.safeValue ?? 0) mg/dL")
        return readings
    }
}
