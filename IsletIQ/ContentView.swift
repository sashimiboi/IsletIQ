//
//  ContentView.swift
//  IsletIQ
//
//  Created by Anthony Loya on 4/3/26.
//

import SwiftUI
import SwiftData
import HealthKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingLogEntry = false
    @State private var showingMealLog = false
    @State private var showingLogInsulin = false
    @State private var hasSeeded = false
    @State private var dexcomManager = DexcomManager()
    @State private var healthKit = HealthKitManager()
    @State private var notifications = NotificationManager()
    @State private var isAuthenticated = APIConfig.authToken != nil
    private let watchSync = WatchSyncManager.shared
    private let medicationClient = MedicationClient()

    var body: some View {
        if !isAuthenticated {
            AuthView {
                isAuthenticated = true
            }
        } else {
        #if os(macOS)
        NavigationSplitView {
            sidebarContent
        } detail: {
            DashboardView(dexcomManager: dexcomManager, healthKit: healthKit)
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear(perform: seedIfNeeded)
        .sheet(isPresented: $showingLogEntry) {
            LogEntryView()
        }
        #else
        TabView {
            NavigationStack {
                DashboardView(dexcomManager: dexcomManager, healthKit: healthKit)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button { showingLogEntry = true } label: {
                                    Label("Log Glucose", systemImage: "drop.fill")
                                }
                                Button { showingMealLog = true } label: {
                                    Label("Log Meal", systemImage: "fork.knife")
                                }
                                Button { showingLogInsulin = true } label: {
                                    Label("Log Insulin", systemImage: "syringe")
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.primary)
                            }
                        }
                    }
            }
            .tabItem {
                Label("CGM", systemImage: "waveform.path.ecg")
            }

            NavigationStack {
                NutritionView(healthKit: healthKit)
            }
            .tabItem {
                Label("Health", systemImage: "heart.text.square")
            }

            NavigationStack {
                AgentChatView(dexcomManager: dexcomManager, healthKit: healthKit, medicationClient: medicationClient)
            }
            .tabItem {
                Label("Agent", systemImage: "sparkles")
            }

            NavigationStack {
                SupplyTrackerView()
            }
            .tabItem {
                Label("Supplies", systemImage: "shippingbox")
            }

            NavigationStack {
                SettingsView(dexcomManager: dexcomManager)
            }
            .tabItem {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .tint(Theme.primary)
        .onAppear {
            // Seed in background so it doesn't block UI
            // Seed only if DB is empty - runs in background
            Task(priority: .background) {
                seedIfNeeded()
            }
            // HealthKit auth + data fetch
            Task(priority: .userInitiated) {
                await healthKit.requestAuthorization()
                await healthKit.fetchAll()
            }
            // Dexcom
            if dexcomManager.isLoggedIn {
                Task(priority: .userInitiated) {
                    await dexcomManager.fetchLatest()
                    dexcomManager.startAutoRefresh()
                    syncToWatch()
                }
            } else {
                syncToWatch()
            }
            // Push data to backend (parallel, non-blocking with timeout)
            Task(priority: .background) {
                try? await Task.sleep(for: .seconds(3))
                async let s: () = pushSleepToBackend()
                async let m: () = pushMealsToBackend()
                async let p: () = pushPumpToBackend()
                _ = await (s, m, p)
            }
            // Re-push meals/pump every 2 minutes
            Task(priority: .background) {
                try? await Task.sleep(for: .seconds(120))
                while !Task.isCancelled {
                    await healthKit.fetchRecentMeals()
                    async let m: () = pushMealsToBackend()
                    async let p: () = pushPumpToBackend()
                    _ = await (m, p)
                    try? await Task.sleep(for: .seconds(120))
                }
            }
            // Notifications + medication reminders
            Task(priority: .background) {
                await notifications.requestAuthorization()
                notifications.scheduleMealReminders()
                let meds = await medicationClient.fetchMedications()
                notifications.scheduleMedicationReminders(meds)
            }
        }
        // Check glucose for alerts + sync to watch when readings update
        .onChange(of: dexcomManager.liveReadings.count) {
            if let latest = dexcomManager.liveReadings.first {
                notifications.checkGlucose(value: latest.safeValue, trend: latest.trendArrow)
                // TODO: Wire up real sensor/pump data when pump integration is available
                // notifications.checkSensor(daysRemaining: sensorDaysRemaining)
                // notifications.checkPump(reservoirUnits: reservoirUnits, podDaysRemaining: podDaysRemaining)

                // Sync to Apple Watch via Bluetooth
                let spark = Array(dexcomManager.liveReadings.prefix(6).reversed().map(\.safeValue))
                let allVals = dexcomManager.liveReadings.map(\.safeValue)
                let avg = allVals.isEmpty ? 0 : allVals.reduce(0, +) / allVals.count
                let inRange = allVals.filter { $0 >= 70 && $0 <= 180 }.count
                let tir = allVals.isEmpty ? 0 : Int(Double(inRange) / Double(allVals.count) * 100)
                let status: String = latest.safeValue < 70 ? "Low" : latest.safeValue <= 180 ? "In Range" : latest.safeValue <= 250 ? "High" : "Urgent High"
                let color: String = latest.safeValue < 70 ? "low" : latest.safeValue <= 180 ? "normal" : latest.safeValue <= 250 ? "elevated" : "high"

                watchSync.syncGlucose(
                    value: latest.safeValue,
                    trend: latest.trendArrow.rawValue,
                    trendSymbol: latest.trendArrow.symbol,
                    status: status,
                    statusColor: color,
                    sparkline: spark,
                    tir: tir,
                    avg: avg,
                    readingCount: allVals.count
                )
            }
        }
        .sheet(isPresented: $showingLogEntry) {
            LogEntryView()
        }
        .sheet(isPresented: $showingMealLog) {
            LogMealView(healthKit: healthKit)
        }
        .sheet(isPresented: $showingLogInsulin) {
            LogInsulinView(healthKit: healthKit)
        }
        #endif
        } // end isAuthenticated
    }

    private func syncToWatch() {
        // Use CSV/stored data if no live readings
        let readings: [(value: Int, trend: TrendArrow)] = {
            if !dexcomManager.liveReadings.isEmpty {
                return dexcomManager.liveReadings.map { (value: $0.safeValue, trend: $0.trendArrow) }
            }
            // Fall back to MockData
            let stored = MockData.glucoseReadings()
            return stored.suffix(288).map { (value: $0.value, trend: $0.trendArrow) }
        }()

        guard let latest = readings.first else { return }

        let spark = Array(readings.prefix(6).reversed().map(\.value))
        let allVals = readings.map(\.value)
        let avg = allVals.isEmpty ? 0 : allVals.reduce(0, +) / allVals.count
        let inRange = allVals.filter { $0 >= 70 && $0 <= 180 }.count
        let tir = allVals.isEmpty ? 0 : Int(Double(inRange) / Double(allVals.count) * 100)
        let status: String = latest.value < 70 ? "Low" : latest.value <= 180 ? "In Range" : latest.value <= 250 ? "High" : "Urgent High"
        let color: String = latest.value < 70 ? "low" : latest.value <= 180 ? "normal" : latest.value <= 250 ? "elevated" : "high"

        watchSync.syncGlucose(
            value: latest.value,
            trend: latest.trend.rawValue,
            trendSymbol: latest.trend.symbol,
            status: status,
            statusColor: color,
            sparkline: spark,
            tir: tir,
            avg: avg,
            readingCount: allVals.count
        )

        // Push CGM + sleep data to backend for watch to read
        Task {
            await pushCGMToBackend(value: latest.value, trend: latest.trend, status: status, statusColor: color, sparkline: spark, tir: tir, avg: avg, readingCount: allVals.count)
            await pushSleepToBackend()
            await pushMealsToBackend()
            await pushPumpToBackend()
        }
    }

    private func pushSleepToBackend() async {
        guard let sleep = healthKit.lastSleep else { return }
        guard let url = URL(string: "\(APIConfig.baseURL)/api/sleep/push") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)

        let segments = sleep.segments.map { seg -> [String: Any] in
            ["stage": seg.stage.rawValue,
             "start": seg.start.timeIntervalSince1970,
             "end": seg.end.timeIntervalSince1970,
             "minutes": seg.durationMinutes]
        }

        let body: [String: Any] = [
            "totalHours": sleep.totalHours,
            "quality": sleep.quality,
            "deepMinutes": sleep.deepMinutes,
            "remMinutes": sleep.remMinutes,
            "coreMinutes": sleep.coreMinutes,
            "awakeMinutes": sleep.awakeMinutes,
            "bedtime": sleep.bedtime.timeIntervalSince1970,
            "wakeTime": sleep.wakeTime.timeIntervalSince1970,
            "segments": segments,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    private func pushPumpToBackend() async {
        guard let insulinType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else { return }
        guard let url = URL(string: "\(APIConfig.baseURL)/api/pump/push") else { return }

        let startOfDay = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: .now, options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: insulinType,
                predicate: predicate,
                limit: 50,
                sortDescriptors: [sortDesc]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthKit.store.execute(query)
        }

        guard !samples.isEmpty else { return }

        // Separate basal vs bolus
        var totalBasal = 0.0
        var boluses: [[String: Any]] = []
        var lastBolusUnits = 0.0

        for sample in samples {
            let units = sample.quantity.doubleValue(for: .internationalUnit())
            let reason = sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? Int
            if reason == HKInsulinDeliveryReason.basal.rawValue {
                totalBasal += units
            } else {
                if boluses.isEmpty { lastBolusUnits = units }
                boluses.append([
                    "units": units,
                    "carbs": 0,
                    "timestamp": sample.startDate.timeIntervalSince1970
                ])
            }
        }

        // Estimate hourly basal rate from today's total basal delivery
        let hoursElapsed = max(1, Date().timeIntervalSince(startOfDay) / 3600.0)
        let basalRate = totalBasal / hoursElapsed

        let body: [String: Any] = [
            "model": "Omnipod 5",
            "basalRate": round(basalRate * 100) / 100,
            "lastBolus": lastBolusUnits,
            "reservoir": 200.0 - totalBasal - boluses.reduce(0.0) { $0 + ($1["units"] as? Double ?? 0) },
            "battery": 100,
            "recentBoluses": Array(boluses.prefix(5))
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    private func pushMealsToBackend() async {
        let meals = healthKit.recentMeals.filter { Calendar.current.isDateInToday($0.date) }
        guard let url = URL(string: "\(APIConfig.baseURL)/api/meals/push") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        let mealsData = meals.map { m -> [String: Any] in
            ["name": m.name, "carbs": Int(m.carbs), "calories": Int(m.calories)]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["meals": mealsData])
        _ = try? await URLSession.shared.data(for: request)
    }

    private func pushCGMToBackend(value: Int, trend: TrendArrow, status: String, statusColor: String, sparkline: [Int], tir: Int, avg: Int, readingCount: Int) async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/cgm/push") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        let body: [String: Any] = [
            "glucose": value,
            "trend": trend.rawValue,
            "trendSymbol": trend.symbol,
            "status": status,
            "statusColor": statusColor,
            "sparkline": sparkline,
            "tir": tir,
            "avg": avg,
            "readingCount": readingCount,
            "timestamp": Date().timeIntervalSince1970,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    #if os(macOS)
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("IsletLogo")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("IsletIQ")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            List {
                NavigationLink {
                    DashboardView(dexcomManager: dexcomManager, healthKit: healthKit)
                } label: {
                    Label("CGM", systemImage: "chart.line.uptrend.xyaxis")
                }
                NavigationLink {
                    PumpView(healthKit: healthKit)
                } label: {
                    Label("Pump", systemImage: "cross.vial.fill")
                }
                NavigationLink {
                    AgentChatView(dexcomManager: dexcomManager, healthKit: healthKit, medicationClient: medicationClient)
                } label: {
                    Label("Agent", systemImage: "brain.head.profile.fill")
                }
                NavigationLink {
                    MarketplaceView()
                } label: {
                    Label("Apps", systemImage: "square.grid.2x2.fill")
                }
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink {
                    SettingsView(dexcomManager: dexcomManager)
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .listStyle(.sidebar)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .toolbar {
            ToolbarItem {
                Button { showingLogEntry = true } label: {
                    Label("Log Reading", systemImage: "plus")
                }
            }
        }
    }
    #endif

    private func seedIfNeeded() {
        guard !hasSeeded else { return }
        hasSeeded = true

        let descriptor = FetchDescriptor<GlucoseReading>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        // Only seed last 7 days to keep it fast (not all 19K readings)
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let readings = MockData.glucoseReadings().filter { $0.timestamp >= cutoff }
        for reading in readings {
            modelContext.insert(reading)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: GlucoseReading.self, inMemory: true)
}
