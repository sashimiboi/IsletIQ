import Foundation
import UserNotifications

@Observable
class NotificationManager {
    var isAuthorized = false

    private let center = UNUserNotificationCenter.current()
    // Throttle: track last fire time per notification ID (persisted in UserDefaults)
    private static let throttleKey = "notif_throttle"
    private static let throttleInterval: TimeInterval = 3600 // 1 hour minimum between same alerts

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
        // Clean up old entries (> 24h)
        let cutoff = Date().timeIntervalSince1970 - 86400
        throttle = throttle.filter { $0.value > cutoff }
        defaults.set(throttle, forKey: Self.throttleKey)
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run { isAuthorized = granted }
        } catch {
            print("[notifications] Auth error: \(error)")
        }
    }

    func checkAuthorization() async {
        let settings = await center.notificationSettings()
        await MainActor.run {
            isAuthorized = settings.authorizationStatus == .authorized
        }
    }

    // MARK: - CGM Alerts

    func checkGlucose(value: Int, trend: TrendArrow) {
        guard isAuthorized else { return }

        if value < 55 {
            sendImmediate(
                id: "cgm-urgent-low",
                title: "Urgent Low - \(value) mg/dL",
                body: "Treat immediately. Take 15g fast-acting carbs now.",
                category: "cgm",
                sound: .defaultCritical
            )
        } else if value < 70 {
            sendImmediate(
                id: "cgm-low",
                title: "Low Glucose - \(value) mg/dL",
                body: "Consider eating 15g carbs. Trend: \(trend.rawValue)",
                category: "cgm"
            )
        } else if value > 300 {
            sendImmediate(
                id: "cgm-urgent-high",
                title: "Urgent High - \(value) mg/dL",
                body: "Check for ketones. Consider a correction bolus.",
                category: "cgm",
                sound: .defaultCritical
            )
        } else if value > 250 {
            sendImmediate(
                id: "cgm-high",
                title: "High Glucose - \(value) mg/dL",
                body: "Consider a correction dose. Trend: \(trend.rawValue)",
                category: "cgm"
            )
        }

        // Rapid drop alert
        if trend == .fallingFast && value < 120 {
            sendImmediate(
                id: "cgm-falling-fast",
                title: "Falling Fast - \(value) mg/dL",
                body: "Glucose dropping rapidly. Consider eating carbs soon.",
                category: "cgm"
            )
        }
    }

    // MARK: - Supply Alerts

    func checkSupplies(_ supplies: [RemoteSupply]) {
        guard isAuthorized else { return }

        for supply in supplies {
            if supply.quantity <= 3 && supply.quantity > 0 {
                sendImmediate(
                    id: "supply-low-\(supply.id)",
                    title: "Low Supply - \(supply.name)",
                    body: "Only \(supply.quantity) left (\(supply.daysRemaining) days). Time to reorder.",
                    category: "supply"
                )
            } else if supply.quantity == 0 {
                sendImmediate(
                    id: "supply-out-\(supply.id)",
                    title: "Out of \(supply.name)",
                    body: "You have 0 left. Reorder immediately.",
                    category: "supply",
                    sound: .defaultCritical
                )
            }
        }
    }

    // MARK: - Pump Alerts

    func checkPump(reservoirUnits: Double, podDaysRemaining: Int) {
        guard isAuthorized else { return }

        if reservoirUnits < 20 {
            sendImmediate(
                id: "pump-reservoir-low",
                title: "Low Reservoir - \(Int(reservoirUnits))u",
                body: "Prepare a new pod. Reservoir running low.",
                category: "pump"
            )
        }

        if podDaysRemaining <= 0 {
            sendImmediate(
                id: "pump-pod-expired",
                title: "Pod Expired",
                body: "Your pod has expired. Change it now.",
                category: "pump",
                sound: .defaultCritical
            )
        } else if podDaysRemaining == 1 {
            sendImmediate(
                id: "pump-pod-expiring",
                title: "Pod Expiring Soon",
                body: "Your pod expires tomorrow. Have a new one ready.",
                category: "pump"
            )
        }
    }

    func checkSensor(daysRemaining: Int) {
        guard isAuthorized else { return }

        if daysRemaining <= 0 {
            sendImmediate(
                id: "cgm-sensor-expired",
                title: "Sensor Expired",
                body: "Your Dexcom G7 sensor has expired. Insert a new one.",
                category: "cgm",
                sound: .defaultCritical
            )
        } else if daysRemaining == 1 {
            sendImmediate(
                id: "cgm-sensor-expiring",
                title: "Sensor Expiring Soon",
                body: "Your Dexcom G7 sensor expires tomorrow. Have a new one ready.",
                category: "cgm"
            )
        }
    }

    // MARK: - Meal Reminders

    func scheduleMealReminders() {
        guard isAuthorized else { return }

        // Remove old meal reminders
        center.removePendingNotificationRequests(withIdentifiers: ["meal-breakfast", "meal-lunch", "meal-dinner"])

        scheduleDailyReminder(id: "meal-breakfast", title: "Log Breakfast", body: "Don't forget to log your breakfast and bolus.", hour: 9, minute: 0)
        scheduleDailyReminder(id: "meal-lunch", title: "Log Lunch", body: "Time to log lunch. Open IsletIQ to estimate carbs.", hour: 13, minute: 0)
        scheduleDailyReminder(id: "meal-dinner", title: "Log Dinner", body: "Remember to log dinner for accurate tracking.", hour: 19, minute: 0)
    }

    func cancelMealReminders() {
        center.removePendingNotificationRequests(withIdentifiers: ["meal-breakfast", "meal-lunch", "meal-dinner"])
    }

    // MARK: - Medication Reminders

    func scheduleMedicationReminders(_ medications: [Medication]) {
        guard isAuthorized else { return }

        // Remove existing medication reminders
        center.getPendingNotificationRequests { requests in
            let medIds = requests.filter { $0.identifier.hasPrefix("med-") }.map(\.identifier)
            self.center.removePendingNotificationRequests(withIdentifiers: medIds)
        }

        for med in medications where med.isActive {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"

            for time in med.scheduleTimes {
                guard let date = formatter.date(from: time) else { continue }
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)

                scheduleDailyReminder(
                    id: "med-\(med.id)-\(time)",
                    title: "Take \(med.name)",
                    body: med.dosage.isEmpty ? "Time for your medication" : "\(med.dosage) — tap to log",
                    hour: components.hour ?? 8,
                    minute: components.minute ?? 0
                )
            }
        }
    }

    func cancelMedicationReminders() {
        center.getPendingNotificationRequests { requests in
            let medIds = requests.filter { $0.identifier.hasPrefix("med-") }.map(\.identifier)
            self.center.removePendingNotificationRequests(withIdentifiers: medIds)
        }
    }

    // MARK: - Helpers

    private func sendImmediate(id: String, title: String, body: String, category: String, sound: UNNotificationSound = .default) {
        // Throttle: don't fire the same alert more than once per hour
        guard shouldFire(id: id) else { return }
        markFired(id: id)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.categoryIdentifier = category
        content.threadIdentifier = category

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.add(request) { error in
            if let error { print("[notifications] Error: \(error)") }
        }
    }

    private func scheduleDailyReminder(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "meal"

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.add(request) { error in
            if let error { print("[notifications] Schedule error: \(error)") }
        }
    }

    // Cancel all
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
