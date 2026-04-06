//
//  ContentView.swift
//  IsletIQ
//
//  Created by Anthony Loya on 4/3/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingLogEntry = false
    @State private var showingMealLog = false
    @State private var showingLogInsulin = false
    @State private var hasSeeded = false
    @State private var dexcomManager = DexcomManager()
    @State private var healthKit = HealthKitManager()
    @State private var notifications = NotificationManager()
    private let watchSync = WatchSyncManager.shared

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebarContent
        } detail: {
            DashboardView(dexcomManager: dexcomManager)
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear(perform: seedIfNeeded)
        .sheet(isPresented: $showingLogEntry) {
            LogEntryView()
        }
        #else
        TabView {
            NavigationStack {
                DashboardView(dexcomManager: dexcomManager)
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
                AgentChatView(dexcomManager: dexcomManager, healthKit: healthKit)
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
            seedIfNeeded()
            // Delay HealthKit auth so it doesn't compete with other startup tasks
            Task {
                try? await Task.sleep(for: .seconds(2))
                await healthKit.requestAuthorization()
            }
            if dexcomManager.isLoggedIn {
                Task {
                    await dexcomManager.fetchLatest()
                    dexcomManager.startAutoRefresh()
                    // Sync to watch immediately after first fetch
                    syncToWatch()
                }
            } else {
                // Even without Dexcom, sync CSV data to watch
                syncToWatch()
            }
            // Notifications
            Task {
                await notifications.requestAuthorization()
                notifications.scheduleMealReminders()
            }
        }
        // Check glucose for alerts + sync to watch when readings update
        .onChange(of: dexcomManager.liveReadings.count) {
            if let latest = dexcomManager.liveReadings.first {
                notifications.checkGlucose(value: latest.safeValue, trend: latest.trendArrow)
                notifications.checkSensor(daysRemaining: MockData.sensorDaysRemaining)
                notifications.checkPump(reservoirUnits: MockData.reservoirUnits, podDaysRemaining: 2)

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

        // Push CGM data to backend for watch to read
        Task {
            await pushCGMToBackend(value: latest.value, trend: latest.trend, status: status, statusColor: color, sparkline: spark, tir: tir, avg: avg, readingCount: allVals.count)
        }
    }

    private func pushCGMToBackend(value: Int, trend: TrendArrow, status: String, statusColor: String, sparkline: [Int], tir: Int, avg: Int, readingCount: Int) async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/cgm/push") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                    DashboardView(dexcomManager: dexcomManager)
                } label: {
                    Label("CGM", systemImage: "chart.line.uptrend.xyaxis")
                }
                NavigationLink {
                    PumpView()
                } label: {
                    Label("Pump", systemImage: "cross.vial.fill")
                }
                NavigationLink {
                    AgentChatView(dexcomManager: dexcomManager, healthKit: healthKit)
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

        for reading in MockData.glucoseReadings() {
            modelContext.insert(reading)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: GlucoseReading.self, inMemory: true)
}
