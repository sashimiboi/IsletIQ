import Foundation

/// LibreLink Up API client for FreeStyle Libre CGM data.
/// Unofficial API — reverse-engineered from the LibreLink Up mobile app.
actor LibreLinkClient {
    // Regional base URLs — user selects during login
    enum Region: String, CaseIterable {
        case us = "us"
        case eu = "eu"
        case de = "de"
        case fr = "fr"
        case jp = "jp"
        case ap = "ap"  // Asia-Pacific
        case au = "au"

        var baseURL: String {
            switch self {
            case .us: return "https://api-us.libreview.io"
            case .eu: return "https://api-eu.libreview.io"
            case .de: return "https://api-de.libreview.io"
            case .fr: return "https://api-fr.libreview.io"
            case .jp: return "https://api-jp.libreview.io"
            case .ap: return "https://api-ap.libreview.io"
            case .au: return "https://api-au.libreview.io"
            }
        }

        var displayName: String {
            switch self {
            case .us: return "United States"
            case .eu: return "Europe"
            case .de: return "Germany"
            case .fr: return "France"
            case .jp: return "Japan"
            case .ap: return "Asia-Pacific"
            case .au: return "Australia"
            }
        }
    }

    struct GlucoseReading: Codable {
        let Value: Double?
        let Timestamp: String?
        let TrendArrow: Int?
        let isHigh: Bool?
        let isLow: Bool?

        var mgDl: Int { Int(Value ?? 0) }

        var trend: String {
            switch TrendArrow ?? 0 {
            case 1: return "FallingFast"
            case 2: return "Falling"
            case 3: return "Flat"
            case 4: return "Rising"
            case 5: return "RisingFast"
            default: return "Flat"
            }
        }
    }

    struct Connection: Codable {
        let patientId: String?
        let firstName: String?
        let lastName: String?
    }

    enum LibreError: LocalizedError {
        case invalidCredentials
        case regionRedirect(String)
        case networkError(String)
        case noData
        case noConnections

        var errorDescription: String? {
            switch self {
            case .invalidCredentials: return "Invalid LibreLink credentials"
            case .regionRedirect(let region): return "Account is in region: \(region)"
            case .networkError(let msg): return "Network error: \(msg)"
            case .noData: return "No glucose data available"
            case .noConnections: return "No LibreLink Up connections found"
            }
        }
    }

    private var authToken: String?
    private var region: Region

    init(region: Region = .us) {
        self.region = region
    }

    // MARK: - Auth

    /// Login to LibreLink Up. Returns auth token.
    func login(email: String, password: String) async throws -> String {
        let url = URL(string: "\(region.baseURL)/llu/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("4.7.0", forHTTPHeaderField: "version")
        request.setValue("llu.android", forHTTPHeaderField: "product")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LibreError.networkError("Invalid response")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let status = json["status"] as? Int ?? http.statusCode

        // Handle region redirect (status 2 = wrong region)
        if status == 2, let redirectData = json["data"] as? [String: Any],
           let redirect = redirectData["redirect"] as? Bool, redirect,
           let newRegion = redirectData["region"] as? String {
            throw LibreError.regionRedirect(newRegion)
        }

        guard status == 0 || http.statusCode == 200 else {
            throw LibreError.invalidCredentials
        }

        guard let authData = json["data"] as? [String: Any],
              let authTicket = authData["authTicket"] as? [String: Any],
              let token = authTicket["token"] as? String else {
            throw LibreError.networkError("Missing auth token in response")
        }

        self.authToken = token
        return token
    }

    // MARK: - Connections

    /// Get list of connected patients (for LibreLink Up followers).
    func getConnections() async throws -> [Connection] {
        guard let token = authToken else { throw LibreError.invalidCredentials }

        let url = URL(string: "\(region.baseURL)/llu/connections")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("4.7.0", forHTTPHeaderField: "version")
        request.setValue("llu.android", forHTTPHeaderField: "product")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let dataArray = json["data"] as? [[String: Any]] else {
            throw LibreError.noConnections
        }

        return dataArray.compactMap { conn in
            Connection(
                patientId: conn["patientId"] as? String,
                firstName: conn["firstName"] as? String,
                lastName: conn["lastName"] as? String
            )
        }
    }

    // MARK: - Glucose Data

    /// Fetch glucose readings for a connected patient.
    func fetchReadings(patientId: String) async throws -> [GlucoseReading] {
        guard let token = authToken else { throw LibreError.invalidCredentials }

        let url = URL(string: "\(region.baseURL)/llu/connections/\(patientId)/graph")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("4.7.0", forHTTPHeaderField: "version")
        request.setValue("llu.android", forHTTPHeaderField: "product")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let graphData = json["data"] as? [String: Any],
              let connection = graphData["connection"] as? [String: Any] else {
            throw LibreError.noData
        }

        var readings: [GlucoseReading] = []

        // Current reading
        if let current = connection["glucoseMeasurement"] as? [String: Any] {
            let reading = GlucoseReading(
                Value: current["Value"] as? Double ?? current["ValueInMgPerDl"] as? Double,
                Timestamp: current["Timestamp"] as? String ?? current["FactoryTimestamp"] as? String,
                TrendArrow: current["TrendArrow"] as? Int,
                isHigh: current["isHigh"] as? Bool,
                isLow: current["isLow"] as? Bool
            )
            readings.append(reading)
        }

        // Historical graph data
        if let graphPoints = graphData["graphData"] as? [[String: Any]] {
            for point in graphPoints {
                let reading = GlucoseReading(
                    Value: point["Value"] as? Double ?? point["ValueInMgPerDl"] as? Double,
                    Timestamp: point["Timestamp"] as? String ?? point["FactoryTimestamp"] as? String,
                    TrendArrow: nil,
                    isHigh: point["isHigh"] as? Bool,
                    isLow: point["isLow"] as? Bool
                )
                readings.append(reading)
            }
        }

        return readings
    }
}
