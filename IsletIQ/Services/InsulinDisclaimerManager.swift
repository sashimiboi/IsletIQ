import Foundation
import SwiftUI

/// Tracks whether the user has acknowledged the insulin-dose / medical
/// disclaimer for the current app session. Reset to false when the app
/// transitions to background, so a fresh acknowledgment is required each
/// time the user returns to the app.
///
/// Used by views that surface insulin-dose calculations or AI-generated
/// medical recommendations (e.g., AgentChatView). The session-scope is
/// what App Store Review Guideline 1.4.1 effectively requires for non-FDA
/// medical-info apps that perform dose math.
@Observable
final class InsulinDisclaimerManager {
    static let shared = InsulinDisclaimerManager()

    private(set) var acknowledgedThisSession: Bool = false

    private init() {}

    func acknowledge() {
        acknowledgedThisSession = true
    }

    func resetForNewSession() {
        acknowledgedThisSession = false
    }
}
