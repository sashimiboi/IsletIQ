import Foundation

enum APIConfig {
    // AWS ECS Fargate behind ALB, served via custom domain with ACM cert
    nonisolated static let cloudURL = "https://api.isletiq.com"
    // Mac LAN IP for on-device development against localhost backend
    nonisolated static let macIP = "192.168.1.87"
    // Set to true to force device builds to hit the Mac over LAN instead of prod
    nonisolated static let useLocalBackendOnDevice = false

    // Auth token, stored in Keychain only.
    nonisolated static var authToken: String? {
        get { KeychainHelper.load(key: "auth_token") }
        set {
            if let val = newValue {
                KeychainHelper.save(key: "auth_token", value: val)
            } else {
                KeychainHelper.delete(key: "auth_token")
            }
        }
    }

    nonisolated static var baseURL: String {
        // 127.0.0.1 instead of localhost: uvicorn binds IPv4 only by
        // default, and Mac URLSession's Happy Eyeballs tries ::1 first,
        // which refuses and stalls. Forcing IPv4 sidesteps the race.
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8000"
        #elseif os(macOS) && DEBUG
        // Native Mac dev runs alongside the local backend on the same
        // machine. Release Mac builds still hit cloudURL.
        return "http://127.0.0.1:8000"
        #else
        return useLocalBackendOnDevice ? "http://\(macIP):8000" : cloudURL
        #endif
    }

    nonisolated static var baseURLSync: String { baseURL }

    nonisolated static func applyAuth(to request: inout URLRequest) {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
