import Foundation

enum APIConfig {
    // AWS ECS Fargate behind ALB, served via custom domain with ACM cert
    static let cloudURL = "https://api.isletiq.com"
    // Local dev fallback
    static let macIP = "192.168.1.65"

    // Auth token, stored in Keychain only.
    static var authToken: String? {
        get { KeychainHelper.load(key: "auth_token") }
        set {
            if let val = newValue {
                KeychainHelper.save(key: "auth_token", value: val)
            } else {
                KeychainHelper.delete(key: "auth_token")
            }
        }
    }

    @MainActor static var baseURL: String {
        #if targetEnvironment(simulator)
        return "http://localhost:8000"
        #else
        return cloudURL
        #endif
    }

    // Non-isolated version for actors
    nonisolated static var baseURLSync: String {
        #if targetEnvironment(simulator)
        "http://localhost:8000"
        #else
        cloudURL
        #endif
    }

    /// Apply auth header to a request
    static func applyAuth(to request: inout URLRequest) {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
