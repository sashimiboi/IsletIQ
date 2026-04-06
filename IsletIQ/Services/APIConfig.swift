import Foundation

enum APIConfig {
    // AWS ECS Fargate + ALB (stable URL)
    static let cloudURL = "http://isletiq-alb-1046434082.us-east-1.elb.amazonaws.com"
    // Local dev fallback
    static let macIP = "192.168.1.87"

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
}
