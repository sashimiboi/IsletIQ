import Foundation

enum APIConfig {
    static let macIP = "192.168.1.87"

    @MainActor static var baseURL: String {
        #if targetEnvironment(simulator)
        return "http://localhost:8000"
        #else
        return "http://\(macIP):8000"
        #endif
    }

    // Non-isolated version for actors
    nonisolated static var baseURLSync: String {
        #if targetEnvironment(simulator)
        "http://localhost:8000"
        #else
        "http://\(macIP):8000"
        #endif
    }
}
