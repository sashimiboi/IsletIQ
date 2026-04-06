import Foundation
import WatchConnectivity

@Observable
class WatchSyncManager: NSObject {
    static let shared = WatchSyncManager()
    var isWatchReachable = false

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // Send glucose data to watch
    func syncGlucose(value: Int, trend: String, trendSymbol: String, status: String, statusColor: String,
                     sparkline: [Int], tir: Int, avg: Int, readingCount: Int) {
        guard WCSession.default.activationState == .activated else { return }

        let context: [String: Any] = [
            "glucose": value,
            "trend": trend,
            "trendSymbol": trendSymbol,
            "status": status,
            "statusColor": statusColor,
            "sparkline": sparkline,
            "tir": tir,
            "avg": avg,
            "readingCount": readingCount,
            "timestamp": Date().timeIntervalSince1970,
        ]

        let session = WCSession.default
        print("[watch-sync] State: activated=\(session.activationState == .activated) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")

        // Try all delivery methods
        do {
            try session.updateApplicationContext(context)
            print("[watch-sync] Context sent OK")
        } catch {
            print("[watch-sync] Context failed: \(error.localizedDescription)")
        }

        if session.isReachable {
            session.sendMessage(context, replyHandler: nil, errorHandler: { err in
                print("[watch-sync] Message failed: \(err.localizedDescription)")
            })
            print("[watch-sync] Message sent")
        }

        session.transferUserInfo(context)
        print("[watch-sync] UserInfo queued")
    }

    // Send supply data to watch
    func syncSupplies(_ supplies: [(name: String, quantity: Int, daysLeft: Int, urgent: Bool)]) {
        guard WCSession.default.activationState == .activated else { return }

        let supplyData = supplies.map { s -> [String: Any] in
            ["name": s.name, "quantity": s.quantity, "daysLeft": s.daysLeft, "urgent": s.urgent]
        }

        // Merge with existing context
        var context = WCSession.default.applicationContext
        context["supplies"] = supplyData
        try? WCSession.default.updateApplicationContext(context)
    }
}

extension WatchSyncManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for watch switching
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }

    // Watch requested an update
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "glucose_update" {
            // The ContentView will handle this via onChange
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .watchRequestedUpdate, object: nil)
            }
        }

        // Watch logged a meal
        if message["action"] as? String == "log_meal" {
            let name = message["name"] as? String ?? "Snack"
            let carbs = message["carbs"] as? Int ?? 0
            Task {
                let hk = HealthKitManager()
                await hk.requestAuthorization()
                await hk.logMeal(name: name, calories: Double(carbs * 4), carbs: Double(carbs), protein: 0, fat: 0)
            }
        }
    }
}

extension Notification.Name {
    static let watchRequestedUpdate = Notification.Name("watchRequestedUpdate")
}
