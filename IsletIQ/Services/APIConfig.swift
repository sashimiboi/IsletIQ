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
        #if targetEnvironment(simulator)
        return "http://localhost:8000"
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
