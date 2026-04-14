import Foundation
import WatchConnectivity
import UserNotifications

// MARK: - Watch Notification Manager

@Observable
class WatchNotificationManager {
    static let shared = WatchNotificationManager()
    var isAuthorized = false

    private let center = UNUserNotificationCenter.current()
    private static let throttleKey = "w_notif_throttle"
    private static let throttleInterval: TimeInterval = 3600

    private init() {}

    private func shouldFire(id: String) -> Bool {
        let defaults = UserDefaults.standard
        let throttle = defaults.dictionary(forKey: Self.throttleKey) as? [String: Double] ?? [:]
        if let lastFire = throttle[id], Date().timeIntervalSince1970 - lastFire < Self.throttleInterval {
            return false
        }
        return true
    }

    private func markFired(id: String) {
        let defaults = UserDefaults.standard
        var throttle = defaults.dictionary(forKey: Self.throttleKey) as? [String: Double] ?? [:]
        throttle[id] = Date().timeIntervalSince1970
        let cutoff = Date().timeIntervalSince1970 - 86400
        throttle = throttle.filter { $0.value > cutoff }
        defaults.set(throttle, forKey: Self.throttleKey)
    }

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            await MainActor.run { isAuthorized = granted }
        } catch {
            print("[watch-notif] Auth error: \(error)")
        }
    }

    func checkGlucose(value: Int, trend: String) {
        guard isAuthorized, value > 0 else { return }

        if value < 55 {
            send(id: "cgm-urgent-low", title: "\(value) mg/dL",
                 body: "Urgent low. Take 15g fast carbs now.", critical: true)
        } else if value < 70 {
            send(id: "cgm-low", title: "\(value) mg/dL",
                 body: "Low glucose. Consider 15g carbs.")
        } else if value > 300 {
            send(id: "cgm-urgent-high", title: "\(value) mg/dL",
                 body: "Urgent high. Check ketones, consider correction.", critical: true)
        } else if value > 250 {
            send(id: "cgm-high", title: "\(value) mg/dL",
                 body: "High glucose. Consider a correction dose.")
        }

        if (trend == "FortyFiveDown" || trend == "SingleDown" || trend == "DoubleDown") && value < 120 {
            send(id: "cgm-falling", title: "Dropping Fast - \(value)",
                 body: "Glucose falling rapidly. Eat carbs soon.")
        }
    }

    func checkSupplies(_ supplies: [(name: String, quantity: Int, daysLeft: Int, urgent: Bool)]) {
        guard isAuthorized else { return }
        for supply in supplies {
            if supply.quantity == 0 {
                send(id: "supply-out-\(supply.name)", title: "Out of \(supply.name)",
                     body: "Reorder immediately.", critical: true)
            } else if supply.urgent {
                send(id: "supply-low-\(supply.name)", title: "Low: \(supply.name)",
                     body: "\(supply.quantity) left (~\(supply.daysLeft) days). Reorder soon.")
            }
        }
    }

    func checkPump(reservoir: Double, battery: Int) {
        guard isAuthorized else { return }
        if reservoir > 0 && reservoir < 20 {
            send(id: "pump-reservoir-low", title: "Low Reservoir - \(Int(reservoir))u",
                 body: "Prepare a new pod.")
        }
        if battery > 0 && battery < 15 {
            send(id: "pump-battery-low", title: "Pump Battery Low - \(battery)%",
                 body: "Charge or replace soon.")
        }
    }

    private func send(id: String, title: String, body: String, critical: Bool = false) {
        guard shouldFire(id: id) else { return }
        markFired(id: id)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = critical ? .defaultCritical : .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("[watch-notif] Error: \(error)") }
        }
    }
}

// MARK: - Watch Connectivity Manager

@Observable
class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    var currentGlucose: Int = 0
    var trend: String = "Flat"
    var trendSymbol: String = "arrow.right"
    var lastUpdate: Date?
    var sparkline: [Int] = []
    var status: String = "--"
    var statusColor: String = "normal"
    var isConnected = false

    var supplies: [(name: String, quantity: Int, daysLeft: Int, urgent: Bool)] = []

    var tir: Int = 0
    var avg: Int = 0
    var readingCount: Int = 0

    // Sleep
    var sleepHours: Double = 0
    var sleepQuality: String = "--"
    var deepMin: Double = 0
    var remMin: Double = 0
    var coreMin: Double = 0
    var awakeMin: Double = 0
    var sleepSegments: [(stage: String, start: Double, end: Double, minutes: Double)] = []

    // Meals
    var recentMeals: [(name: String, carbs: Int, calories: Int)] = []

    // Medications
    var medications: [(name: String, dosage: String, time: String, taken: Bool)] = []

    // Pump
    var basalRate: Double = 0
    var lastBolus: Double = 0
    var reservoir: Double = 0
    var pumpBattery: Int = 0
    var pumpModel: String = "--"
    var recentBoluses: [(units: Double, carbs: Int, timestamp: Double)] = []

    private let apiBase = "https://api.isletiq.com"
    private let notifications = WatchNotificationManager.shared

    private override init() {
        super.init()

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }

        loadCached()
        Task {
            await notifications.requestAuthorization()
            await fetchAll()
        }
        startPeriodicRefresh()
    }

    func refresh() {
        Task { await fetchAll() }
    }

    private func startPeriodicRefresh() {
        // Poll every 60 seconds for near-realtime data
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.fetchCGM() }
        }
        // Full refresh every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.fetchAll() }
        }
    }

    // MARK: - Fetch from AWS Backend

    func fetchAll() async {
        await fetchCGM()
        await fetchSleep()
        await fetchMeals()
        await fetchPump()
        await fetchSupplies()
        await fetchMedications()
        await fetchMetrics()
    }

    private func fetchPump() async {
        guard let url = URL(string: "\(apiBase)/api/pump/latest") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["error"] == nil {
                await MainActor.run {
                    basalRate = json["basalRate"] as? Double ?? 0
                    lastBolus = json["lastBolus"] as? Double ?? 0
                    reservoir = json["reservoir"] as? Double ?? 0
                    pumpBattery = json["battery"] as? Int ?? 0
                    pumpModel = json["model"] as? String ?? "--"
                    if let boluses = json["recentBoluses"] as? [[String: Any]] {
                        recentBoluses = boluses.map { b in
                            (units: b["units"] as? Double ?? 0,
                             carbs: b["carbs"] as? Int ?? 0,
                             timestamp: b["timestamp"] as? Double ?? 0)
                        }
                    }
                    notifications.checkPump(reservoir: reservoir, battery: pumpBattery)
                    print("[watch] Pump loaded: \(pumpModel), reservoir \(Int(reservoir))u")
                }
            }
        } catch {
            print("[watch] Pump fetch: \(error.localizedDescription)")
        }
    }

    private func fetchMeals() async {
        guard let url = URL(string: "\(apiBase)/api/meals/latest") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let meals = json["meals"] as? [[String: Any]] {
                await MainActor.run {
                    recentMeals = meals.map { m in
                        (name: m["name"] as? String ?? "Meal",
                         carbs: m["carbs"] as? Int ?? 0,
                         calories: m["calories"] as? Int ?? 0)
                    }
                    print("[watch] Meals loaded: \(recentMeals.count)")
                }
            }
        } catch {
            print("[watch] Meals fetch: \(error.localizedDescription)")
        }
    }

    private func fetchMedications() async {
        guard let url = URL(string: "\(apiBase)/api/medications/public") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let meds = json["medications"] as? [[String: Any]] {
                await MainActor.run {
                    var result: [(name: String, dosage: String, time: String, taken: Bool)] = []
                    for m in meds {
                        let name = m["name"] as? String ?? ""
                        let dosage = m["dosage"] as? String ?? ""
                        let times = m["schedule_times"] as? [String] ?? []
                        let doses = m["doses"] as? [[String: Any]] ?? []
                        let takenTimes = Set(doses.compactMap { $0["scheduled_time"] as? String })
                        for time in times {
                            result.append((name: name, dosage: dosage, time: time, taken: takenTimes.contains(time)))
                        }
                    }
                    medications = result
                    print("[watch] Medications loaded: \(medications.count)")
                }
            }
        } catch {
            print("[watch] Medications fetch: \(error.localizedDescription)")
        }
    }

    private func fetchSleep() async {
        guard let url = URL(string: "\(apiBase)/api/sleep/latest") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["error"] == nil {
                await MainActor.run {
                    sleepHours = json["totalHours"] as? Double ?? 0
                    sleepQuality = json["quality"] as? String ?? "--"
                    deepMin = json["deepMinutes"] as? Double ?? 0
                    remMin = json["remMinutes"] as? Double ?? 0
                    coreMin = json["coreMinutes"] as? Double ?? 0
                    awakeMin = json["awakeMinutes"] as? Double ?? 0
                    if let segs = json["segments"] as? [[String: Any]] {
                        sleepSegments = segs.map { s in
                            (stage: s["stage"] as? String ?? "Core",
                             start: s["start"] as? Double ?? 0,
                             end: s["end"] as? Double ?? 0,
                             minutes: s["minutes"] as? Double ?? 0)
                        }
                    }
                    print("[watch] Sleep loaded: \(String(format: "%.1f", sleepHours))h")
                }
            }
        } catch {
            print("[watch] Sleep fetch: \(error.localizedDescription)")
        }
    }

    private func fetchCGM() async {
        guard let url = URL(string: "\(apiBase)/api/cgm/latest") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let glucose = json["glucose"] as? Int, glucose > 0 {
                await MainActor.run {
                    currentGlucose = glucose
                    trend = json["trend"] as? String ?? "Flat"
                    trendSymbol = json["trendSymbol"] as? String ?? "arrow.right"
                    status = json["status"] as? String ?? "--"
                    statusColor = json["statusColor"] as? String ?? "normal"
                    sparkline = json["sparkline"] as? [Int] ?? []
                    tir = json["tir"] as? Int ?? 0
                    avg = json["avg"] as? Int ?? 0
                    readingCount = json["readingCount"] as? Int ?? 0
                    lastUpdate = Date()
                    saveToCache()
                    notifications.checkGlucose(value: currentGlucose, trend: trend)
                    print("[watch] CGM loaded: \(currentGlucose) mg/dL, \(readingCount) readings")
                }
            } else {
                print("[watch] CGM: no data or credentials not set")
            }
        } catch {
            print("[watch] CGM fetch: \(error.localizedDescription)")
        }
    }

    private func fetchSupplies() async {
        guard let url = URL(string: "\(apiBase)/api/supplies/public") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["supplies"] as? [[String: Any]] {
                await MainActor.run {
                    supplies = items.map { s in
                        let qty = s["quantity"] as? Int ?? 0
                        let rate = s["usage_rate_days"] as? Double ?? 1
                        return (name: s["name"] as? String ?? "",
                                quantity: qty,
                                daysLeft: Int(Double(qty) * rate),
                                urgent: qty <= 3)
                    }
                    saveToCache()
                    notifications.checkSupplies(supplies)
                    print("[watch] Supplies loaded: \(supplies.count)")
                }
            }
        } catch {
            print("[watch] Supply fetch: \(error.localizedDescription)")
        }
    }

    private func fetchMetrics() async {
        guard let url = URL(string: "\(apiBase)/api/metrics") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                await MainActor.run {
                    readingCount = json["total_requests"] as? Int ?? readingCount
                    saveToCache()
                }
            }
        } catch {
            print("[watch] Metrics fetch: \(error.localizedDescription)")
        }
    }

    func requestUpdate() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "glucose_update"], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Cache

    private func loadCached() {
        let d = UserDefaults.standard
        currentGlucose = d.integer(forKey: "w_glucose")
        trend = d.string(forKey: "w_trend") ?? "Flat"
        trendSymbol = d.string(forKey: "w_trendSymbol") ?? "arrow.right"
        status = d.string(forKey: "w_status") ?? "--"
        statusColor = d.string(forKey: "w_statusColor") ?? "normal"
        tir = d.integer(forKey: "w_tir")
        avg = d.integer(forKey: "w_avg")
        readingCount = d.integer(forKey: "w_readingCount")
        sparkline = d.array(forKey: "w_sparkline") as? [Int] ?? []
        if let ts = d.object(forKey: "w_timestamp") as? Double, ts > 0 {
            lastUpdate = Date(timeIntervalSince1970: ts)
        }
    }

    private func saveToCache() {
        let d = UserDefaults.standard
        d.set(currentGlucose, forKey: "w_glucose")
        d.set(trend, forKey: "w_trend")
        d.set(trendSymbol, forKey: "w_trendSymbol")
        d.set(status, forKey: "w_status")
        d.set(statusColor, forKey: "w_statusColor")
        d.set(tir, forKey: "w_tir")
        d.set(avg, forKey: "w_avg")
        d.set(readingCount, forKey: "w_readingCount")
        d.set(sparkline, forKey: "w_sparkline")
        d.set(lastUpdate?.timeIntervalSince1970 ?? 0, forKey: "w_timestamp")
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.isConnected = activationState == .activated }
        if activationState == .activated { requestUpdate() }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.updateFromWC(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { self.updateFromWC(message) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { self.updateFromWC(userInfo) }
    }

    private func updateFromWC(_ data: [String: Any]) {
        if let glucose = data["glucose"] as? Int { currentGlucose = glucose }
        if let t = data["trend"] as? String { trend = t }
        if let sym = data["trendSymbol"] as? String { trendSymbol = sym }
        if let s = data["status"] as? String { status = s }
        if let c = data["statusColor"] as? String { statusColor = c }
        if let sp = data["sparkline"] as? [Int] { sparkline = sp }
        if let t = data["tir"] as? Int { self.tir = t }
        if let a = data["avg"] as? Int { self.avg = a }
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

        saveToCache()
        notifications.checkGlucose(value: currentGlucose, trend: trend)
        if !supplies.isEmpty { notifications.checkSupplies(supplies) }
        print("[watch] Received WC data: glucose=\(currentGlucose)")
    }
}
