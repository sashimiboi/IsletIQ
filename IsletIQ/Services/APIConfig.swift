import Foundation

enum APIConfig {
    // AWS ECS Fargate + ALB (stable URL)
    static let cloudURL = "https://isletiq-alb-1046434082.us-east-1.elb.amazonaws.com"
    // Local dev fallback
    static let macIP = "192.168.1.87"

    // Auth token
    static var authToken: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
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
