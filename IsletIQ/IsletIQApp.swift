//
//  IsletIQApp.swift
//  IsletIQ
//
//  Created by Anthony Loya on 4/3/26.
//

import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications

// Show notifications even while app is in foreground
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

@main
struct IsletIQApp: App {
    // Background task identifier
    static let bgTaskID = "com.isletiq.refresh"
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            GlucoseReading.self,
        ])

        // Nuke any old database first to avoid schema mismatch crashes
        let defaultURL = URL.applicationSupportDirectory.appending(path: "default.store")
        for ext in ["", "-shm", "-wal"] {
            let fileURL = defaultURL.deletingPathExtension().appendingPathExtension("store\(ext)")
            try? FileManager.default.removeItem(at: fileURL)
        }
        // Also try the standard SwiftData location
        if let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let enumerator = FileManager.default.enumerator(at: containerURL, includingPropertiesForKeys: nil)
            while let fileURL = enumerator?.nextObject() as? URL {
                if fileURL.pathExtension == "store" || fileURL.lastPathComponent.contains("default.store") {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Last resort — try in-memory
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.light)
                .onAppear {
                    registerBackgroundTasks()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgTaskID, using: nil) { task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            handleBackgroundRefresh(bgTask)
        }
        Self.scheduleBackgroundRefresh()
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[bg] Schedule error: \(error)")
        }
    }
}

// Background refresh handler
private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
    // Schedule the next one
    IsletIQApp.scheduleBackgroundRefresh()

    let workTask = Task {
        let notifications = NotificationManager()
        await notifications.checkAuthorization()

        // Check CGM
        let dexcom = DexcomManager()
        if dexcom.isLoggedIn {
            await dexcom.fetchLatest()
            if let latest = dexcom.liveReadings.first {
                notifications.checkGlucose(value: latest.safeValue, trend: latest.trendArrow)
            }
        }

        // Check supplies
        let supplyClient = SupplyClient()
        let supplies = await supplyClient.fetchSupplies()
        let mapped = supplies.map { r in
            RemoteSupply(id: r.id, name: r.name, category: r.category,
                         quantity: r.quantity, usageRateDays: r.usage_rate_days,
                         alertDaysBefore: r.alert_days_before, notes: r.notes ?? "")
        }
        notifications.checkSupplies(mapped)

        task.setTaskCompleted(success: true)
    }

    task.expirationHandler = {
        workTask.cancel()
        task.setTaskCompleted(success: false)
    }
}
