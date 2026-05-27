//
//  IsletIQApp.swift
//  IsletIQ
//
//  Created by Anthony Loya on 4/3/26.
//

import SwiftUI
import SwiftData
import UserNotifications
#if os(iOS)
import UIKit
import BackgroundTasks
#endif

#if os(iOS)
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
#endif

@main
struct IsletIQApp: App {
    #if os(iOS)
    // Background task identifier
    static let bgTaskID = "com.isletiq.refresh"
    #endif
    @State private var containerError: String?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            GlucoseReading.self,
            InsulinEntry.self,
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("[IsletIQ] Persistent store failed: \(error). Falling back to in-memory storage.")
            // Last resort -- in-memory so the app still launches
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memConfig])
            } catch {
                // Absolute last resort -- create a bare container
                print("[IsletIQ] In-memory store also failed: \(error). Creating bare container.")
                // fatalError is explicit about the crash vs a silent try!
                fatalError("[IsletIQ] Cannot create any ModelContainer: \(error)")
            }
        }
    }()

    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.light)
                .onAppear {
                    #if os(iOS)
                    registerBackgroundTasks()
                    #endif
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Reset per-session insulin disclaimer ack when the app
                // goes to background, so the user must re-acknowledge on
                // their next session (App Store guideline 1.4.1).
                InsulinDisclaimerManager.shared.resetForNewSession()
            case .active:
                // Opportunistic Glooko sync on every foreground. Self-throttles
                // to once per hour; no-ops if Glooko isn't connected.
                Task { @MainActor in
                    GlookoSyncManager.shared.performSyncIfNeeded(
                        modelContext: sharedModelContainer.mainContext
                    )
                }
                // Libre / Nightscout / Tidepool foreground pulls. Each no-ops
                // if the user has not connected that integration.
                Task { @MainActor in
                    let ctx = sharedModelContainer.mainContext
                    let libre = LibreManager()
                    if libre.isLoggedIn { await libre.fetchLatest(modelContext: ctx) }
                    let ns = NightscoutManager()
                    if ns.isLoggedIn { await ns.fetchLatest(modelContext: ctx) }
                    let tp = TidepoolManager()
                    if tp.isLoggedIn { await tp.fetchLatest(modelContext: ctx) }
                }
            default:
                break
            }
        }
    }

    #if os(iOS)
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
    #endif
}

#if os(iOS)
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

        // Opportunistic pulls for Libre, Nightscout, Tidepool. Each manager
        // is @MainActor so we hop briefly to check connection state and run
        // its fetch on its own SwiftData context.
        let bgContainer = try? ModelContainer(
            for: GlucoseReading.self, InsulinEntry.self
        )
        if let ctx = bgContainer?.mainContext {
            let libre = await MainActor.run { LibreManager() }
            if await MainActor.run(body: { libre.isLoggedIn }) {
                await libre.fetchLatest(modelContext: ctx)
            }
            let ns = await MainActor.run { NightscoutManager() }
            if await MainActor.run(body: { ns.isLoggedIn }) {
                await ns.fetchLatest(modelContext: ctx)
            }
            let tp = await MainActor.run { TidepoolManager() }
            if await MainActor.run(body: { tp.isLoggedIn }) {
                await tp.fetchLatest(modelContext: ctx)
            }
        }

        task.setTaskCompleted(success: true)
    }

    task.expirationHandler = {
        workTask.cancel()
        task.setTaskCompleted(success: false)
    }
}
#endif
