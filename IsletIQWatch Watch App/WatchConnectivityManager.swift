import Foundation
import WatchConnectivity

@Observable
class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    var currentGlucose: Int = 0
    var trend: String = "Flat"
    var trendSymbol: String = "arrow.right"
    var lastUpdate: Date?
    var sparkline: [Int] = []
    var status: String = "In Range"
    var statusColor: String = "normal"
    var isConnected = false

    var supplies: [(name: String, quantity: Int, daysLeft: Int, urgent: Bool)] = []

    var tir: Int = 0
    var avg: Int = 0
    var readingCount: Int = 0

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }

        // Fetch from API when WatchConnectivity isn't available
        Task { await fetchFromAPI() }
    }

    // Direct API fetch - works on simulator and WiFi watch
    func fetchFromAPI() async {
        let baseURL = "http://localhost:8000"

        // Fetch supplies
        if let url = URL(string: "\(baseURL)/api/supplies") {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["supplies"] as? [[String: Any]] {
                    await MainActor.run {
                        supplies = items.map { s in
                            let qty = s["quantity"] as? Int ?? 0
                            let rate = s["usage_rate_days"] as? Double ?? 1
                            return (
                                name: s["name"] as? String ?? "",
                                quantity: qty,
                                daysLeft: Int(Double(qty) * rate),
                                urgent: qty <= 3
                            )
                        }
                    }
                }
            } catch {}
        }

        // Fetch latest metrics for stats
        if let url = URL(string: "\(baseURL)/api/metrics") {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    await MainActor.run {
                        readingCount = json["total_requests"] as? Int ?? 0
                    }
                }
            } catch {}
        }
    }

    func requestUpdate() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "glucose_update"], replyHandler: nil, errorHandler: nil)
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = activationState == .activated
        }
        if activationState == .activated {
            requestUpdate()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.updateFromContext(applicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.updateFromContext(message)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async {
            self.updateFromContext(userInfo)
        }
    }

    private func updateFromContext(_ data: [String: Any]) {
        if let glucose = data["glucose"] as? Int { currentGlucose = glucose }
        if let t = data["trend"] as? String { trend = t }
        if let sym = data["trendSymbol"] as? String { trendSymbol = sym }
        if let s = data["status"] as? String { status = s }
        if let c = data["statusColor"] as? String { statusColor = c }
        if let sp = data["sparkline"] as? [Int] { sparkline = sp }
        if let tir = data["tir"] as? Int { self.tir = tir }
        if let avg = data["avg"] as? Int { self.avg = avg }
        if let count = data["readingCount"] as? Int { readingCount = count }
        if let ts = data["timestamp"] as? Double { lastUpdate = Date(timeIntervalSince1970: ts) }

        if let supplyData = data["supplies"] as? [[String: Any]] {
            supplies = supplyData.map { s in
                (name: s["name"] as? String ?? "",
                 quantity: s["quantity"] as? Int ?? 0,
                 daysLeft: s["daysLeft"] as? Int ?? 0,
                 urgent: s["urgent"] as? Bool ?? false)
            }
        }
    }
}
