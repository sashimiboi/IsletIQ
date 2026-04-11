import SwiftUI
import UserNotifications

// MARK: - Settings Tabs

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case devices = "Devices"
    case apps = "Apps"
    case evals = "Evals"
    case metrics = "Metrics"
    case traces = "Traces"
    case logs = "Logs"
    case observability = "Observe"
}

struct SettingsView: View {
    var dexcomManager: DexcomManager?
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tabIcon(tab))
                                    .font(.system(size: 11))
                                Text(tab.rawValue)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(selectedTab == tab ? .white : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                selectedTab == tab ? Theme.primary : Theme.muted,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Theme.cardBg)

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 14) {
                    switch selectedTab {
                    case .general: GeneralSettingsContent()
                    case .devices: DevicesSettingsContent(dexcomManager: dexcomManager ?? DexcomManager())
                    case .apps: MarketplaceView()
                    case .evals: EvalsContent()
                    case .metrics: MetricsContent()
                    case .traces: TracesContent()
                    case .logs: LogsContent()
                    case .observability: ObservabilityContent()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func tabIcon(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: "gearshape.fill"
        case .devices: "antenna.radiowaves.left.and.right"
        case .apps: "square.grid.2x2"
        case .evals: "checkmark.seal.fill"
        case .metrics: "chart.bar.fill"
        case .traces: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .logs: "doc.text.fill"
        case .observability: "eye.fill"
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsContent: View {
    @AppStorage("glucoseLow") private var glucoseLow: Int = 70
    @AppStorage("glucoseHigh") private var glucoseHigh: Int = 180
    @AppStorage("userName") private var userName: String = "Anthony Loya"
    @AppStorage("unitPreference") private var unitPreference: String = "mg/dL"
    @AppStorage("notifCGM") private var notifCGM = true
    @AppStorage("notifPump") private var notifPump = true
    @AppStorage("notifSupply") private var notifSupply = true
    @AppStorage("notifMeals") private var notifMeals = true

    var body: some View {
        // Profile
        HStack(spacing: 14) {
            Image("IsletLogo")
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                TextField("Your Name", text: $userName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("IsletIQ")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(20)
        .card()

        // Target range
        VStack(alignment: .leading, spacing: 14) {
            Text("Target Range")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack {
                Text("Low").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(glucoseLow) mg/dL").font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(Theme.low)
            }
            Slider(value: Binding(get: { Double(glucoseLow) }, set: { glucoseLow = Int($0) }), in: 50...100, step: 5).tint(Theme.primary)

            Divider()

            HStack {
                Text("High").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(glucoseHigh) mg/dL").font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(Theme.elevated)
            }
            Slider(value: Binding(get: { Double(glucoseHigh) }, set: { glucoseHigh = Int($0) }), in: 120...250, step: 5).tint(Theme.primary)
        }
        .padding(20)
        .card()

        // Preferences
        VStack(alignment: .leading, spacing: 0) {
            Text("Preferences")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            SettingRow(icon: "ruler", label: "Unit") {
                Picker("", selection: $unitPreference) {
                    Text("mg/dL").tag("mg/dL")
                    Text("mmol/L").tag("mmol/L")
                }.pickerStyle(.menu).tint(Theme.primary)
            }
            Divider().padding(.leading, 52)
        }
        .card()

        // Notifications
        VStack(alignment: .leading, spacing: 0) {
            Text("Notifications")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            SettingRow(icon: "waveform.path.ecg", label: "CGM Alerts") {
                Toggle("", isOn: $notifCGM).labelsHidden().tint(Theme.primary).scaleEffect(0.85)
            }
            Divider().padding(.leading, 52)
            SettingRow(icon: "drop.circle", label: "Pump Alerts") {
                Toggle("", isOn: $notifPump).labelsHidden().tint(Theme.primary).scaleEffect(0.85)
            }
            Divider().padding(.leading, 52)
            SettingRow(icon: "shippingbox", label: "Supply Alerts") {
                Toggle("", isOn: $notifSupply).labelsHidden().tint(Theme.primary).scaleEffect(0.85)
            }
            Divider().padding(.leading, 52)
            SettingRow(icon: "fork.knife", label: "Meal Reminders") {
                Toggle("", isOn: $notifMeals).labelsHidden().tint(Theme.primary).scaleEffect(0.85)
            }
            Divider().padding(.leading, 52)
            SettingRow(icon: "bell.and.waves.left.and.right", label: "Test Notification") {
                Button("Send") {
                    let content = UNMutableNotificationContent()
                    content.title = "Low Glucose - 62 mg/dL"
                    content.body = "Consider eating 15g carbs. Trend: Falling Fast"
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
                    let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.primary)
            }
        }
        .card()

        // Legal & Privacy
        VStack(alignment: .leading, spacing: 0) {
            Text("Legal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            SettingRow(icon: "doc.text", label: "Privacy Policy") {
                Button {
                    if let url = URL(string: "https://isletiq.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Divider().padding(.leading, 52)
            SettingRow(icon: "doc.plaintext", label: "Terms of Service") {
                Button {
                    if let url = URL(string: "https://isletiq.com/terms") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .card()

        // Account
        VStack(alignment: .leading, spacing: 0) {
            Text("Account")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            SettingRow(icon: "rectangle.portrait.and.arrow.right", label: "Log Out") {
                Button("Log Out") {
                    AuthManager().logout()
                    APIConfig.authToken = nil
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.elevated)
            }
            Divider().padding(.leading, 52)
            SettingRow(icon: "trash", label: "Delete Account") {
                Button("Delete") {
                    showDeleteConfirmation = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.high)
            }
        }
        .card()
        .alert("Delete Account", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This will permanently delete your account and all data on our servers. Health data in Apple Health will not be affected. This cannot be undone.")
        }

        // About
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Version").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("1.0.0").font(.subheadline).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .card()
    }

    @State private var showDeleteConfirmation = false

    private func deleteAccount() async {
        guard let url = URL(string: "\(APIConfig.baseURL)/auth/delete-account") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        APIConfig.applyAuth(to: &request)
        _ = try? await URLSession.shared.data(for: request)
        // Clear all local data
        APIConfig.authToken = nil
        KeychainHelper.delete(key: "elevenlabs_api_key")
        KeychainHelper.delete(key: "dexcom_session")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "elevenlabs_voice_id")
    }
}

// MARK: - Devices Settings (CGM/Pump Connection)

struct DevicesSettingsContent: View {
    @State var dexcomManager: DexcomManager
    @State private var showDexcomLogin = false
    @State private var showLibreLogin = false
    @State private var showNightscoutLogin = false
    @State private var showTidepoolLogin = false

    var body: some View {
        // Dexcom G7 — real connection
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dexcom G7")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if dexcomManager.isLoggedIn {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.normal).frame(width: 6, height: 6)
                        Text("Live")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.normal)
                    }
                }
            }

            if dexcomManager.isLoggedIn {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected via Dexcom Share")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        if let sync = dexcomManager.lastSync {
                            Text("Last sync: \(sync, style: .relative) ago")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        if !dexcomManager.liveReadings.isEmpty {
                            Text("\(dexcomManager.liveReadings.count) readings loaded")
                                .font(.caption2)
                                .foregroundStyle(Theme.teal)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await dexcomManager.fetchLatest() }
                    } label: {
                        Text("Sync Now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        dexcomManager.logout()
                    } label: {
                        Text("Disconnect")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.high)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Theme.high.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textTertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not connected")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Connect to get live glucose data every 5 minutes")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()

                    Button {
                        showDexcomLogin = true
                    } label: {
                        Text("Connect")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = dexcomManager.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.high)
            }
        }
        .padding(20)
        .card()
        .sheet(isPresented: $showDexcomLogin) {
            DexcomLoginView(dexcomManager: dexcomManager)
        }

        // FreeStyle Libre (LibreLink Up)
        DeviceIntegrationCard(
            name: "FreeStyle Libre",
            icon: "waveform.path",
            description: "Connect via LibreLink Up to get Libre 2/3 CGM data",
            status: KeychainHelper.load(key: "libre_token") != nil ? "Connected" : "Available",
            statusColor: KeychainHelper.load(key: "libre_token") != nil ? Theme.normal : Theme.teal,
            onConnect: { showLibreLogin = true }
        )
        .sheet(isPresented: $showLibreLogin) { LibreLinkLoginView() }

        // Nightscout
        DeviceIntegrationCard(
            name: "Nightscout",
            icon: "cloud.fill",
            description: "Connect to your Nightscout instance for CGM, treatments, and profile data",
            status: KeychainHelper.load(key: "nightscout_url") != nil ? "Connected" : "Available",
            statusColor: KeychainHelper.load(key: "nightscout_url") != nil ? Theme.normal : Theme.teal,
            onConnect: { showNightscoutLogin = true }
        )
        .sheet(isPresented: $showNightscoutLogin) { NightscoutLoginView() }

        // Tidepool
        DeviceIntegrationCard(
            name: "Tidepool",
            icon: "drop.triangle.fill",
            description: "Sync CGM, pump, and BGM data from Tidepool",
            status: KeychainHelper.load(key: "tidepool_token") != nil ? "Connected" : "Available",
            statusColor: KeychainHelper.load(key: "tidepool_token") != nil ? Theme.normal : Theme.teal,
            onConnect: { showTidepoolLogin = true }
        )
        .sheet(isPresented: $showTidepoolLogin) { TidepoolLoginView() }

        // Omnipod 5
        DeviceIntegrationCard(
            name: "Omnipod 5",
            icon: "circle.hexagongrid.fill",
            description: "Pump data via HealthKit (automatic when Omnipod app is installed)",
            status: "HealthKit",
            statusColor: Theme.normal
        )

        // Tandem t:slim
        DeviceIntegrationCard(
            name: "Tandem t:slim X2 / Mobi",
            icon: "rectangle.connected.to.line.below",
            description: "Pump data via t:connect or Tidepool integration",
            status: "Via Tidepool",
            statusColor: Theme.textTertiary,
            onConnect: { showTidepoolLogin = true }
        )

        // Medtronic
        DeviceIntegrationCard(
            name: "Medtronic 780G / 770G",
            icon: "waveform.badge.plus",
            description: "CGM and pump data via CareLink or Tidepool",
            status: "Via Tidepool",
            statusColor: Theme.textTertiary,
            onConnect: { showTidepoolLogin = true }
        )
    }
}

struct DeviceIntegrationCard: View {
    let name: String
    let icon: String
    let description: String
    let status: String
    let statusColor: Color
    var onConnect: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let onConnect {
                    Button(action: onConnect) {
                        Text(status == "Connected" ? "Settings" : "Connect")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .card()
    }
}

struct DeviceConnectionRow: View {
    let name: String
    let icon: String
    let status: String
    let isConnected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isConnected ? Theme.primary.opacity(0.08) : Theme.muted)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(isConnected ? Theme.primary : Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(isConnected ? Theme.textSecondary : Theme.textTertiary)
            }

            Spacer()

            Button(action: onToggle) {
                Text(isConnected ? "Disconnect" : "Connect")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isConnected ? Theme.high : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        isConnected ? Theme.high.opacity(0.1) : Theme.primary,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Traces (Live from backend)

struct TracesContent: View {
    @State private var traces: [[String: Any]] = []
    @State private var isLoading = true
    private let client = ObservabilityClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Agent Traces")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Text("\(traces.count) traces")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(Theme.primary)
                }.buttonStyle(.plain)
            }

            if traces.isEmpty && !isLoading {
                Text("No traces yet - start a conversation with an agent")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 20)
            }

            ForEach(Array(traces.enumerated()), id: \.offset) { i, trace in
                let status = trace["status"] as? String ?? "unknown"
                let agent = trace["agent"] as? String ?? "-"
                let traceId = (trace["id"] as? String ?? "").prefix(12)
                let duration = trace["duration"] as? Double ?? trace["duration_ms"] as? Double ?? 0
                let spans = trace["spans"] as? [[String: Any]] ?? []
                HStack(spacing: 10) {
                    Circle()
                        .fill(status == "success" ? Theme.normal : status == "error" ? Theme.high : Theme.elevated)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        Text("\(traceId) · \(spans.count) tools · \(String(format: "%.1fs", duration / 1000))")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(status == "success" ? Theme.normal : Theme.high)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((status == "success" ? Theme.normal : Theme.high).opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.vertical, 4)
                if i < traces.count - 1 { Divider() }
            }
        }
        .padding(20)
        .card()
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        traces = await client.fetchTraces(limit: 20)
        isLoading = false
    }
}

// MARK: - Logs (Live from backend)

struct LogsContent: View {
    @State private var logs: [[String: Any]] = []
    @State private var isLoading = true
    @State private var levelFilter = "all"
    private let client = ObservabilityClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("System Logs")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("", selection: $levelFilter) {
                    Text("All").tag("all")
                    Text("Error").tag("error")
                    Text("Info").tag("info")
                    Text("Success").tag("success")
                }.pickerStyle(.menu).tint(Theme.primary)
                    .onChange(of: levelFilter) { _, _ in Task { await load() } }
            }

            if logs.isEmpty && !isLoading {
                Text("No logs yet").font(.caption).foregroundStyle(Theme.textTertiary).padding(.vertical, 20)
            }

            ForEach(Array(logs.enumerated()), id: \.offset) { i, log in
                let level = log["level"] as? String ?? "info"
                let message = log["message"] as? String ?? ""
                let details = log["details"] as? String ?? ""
                let ts = log["timestamp"] as? String ?? log["created_at"] as? String ?? ""
                let timeStr = String(ts.prefix(19)).replacingOccurrences(of: "T", with: " ")
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: logIcon(level)).font(.caption).foregroundStyle(logColor(level)).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message).font(.caption).foregroundStyle(Theme.textPrimary).lineLimit(2)
                        if !details.isEmpty {
                            Text(details).font(.system(size: 9)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                        }
                        Text(timeStr).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                if i < logs.count - 1 { Divider() }
            }
        }
        .padding(20)
        .card()
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        logs = await client.fetchLogs(limit: 30, level: levelFilter)
        isLoading = false
    }

    private func logIcon(_ level: String) -> String {
        switch level {
        case "success": "checkmark.circle.fill"
        case "warning": "exclamationmark.triangle.fill"
        case "error": "xmark.circle.fill"
        default: "info.circle.fill"
        }
    }

    private func logColor(_ level: String) -> Color {
        switch level {
        case "success": Theme.normal
        case "warning": Theme.elevated
        case "error": Theme.high
        default: Theme.teal
        }
    }
}

// MARK: - Evals (Live from backend)

struct EvalsContent: View {
    @State private var summary: [String: Any] = [:]
    @State private var isLoading = true
    @State private var sessions: [(id: String, title: String)] = []
    @State private var selectedSession: String = "all"
    @State private var expandedEval: String? = nil
    private let client = ObservabilityClient()

    var body: some View {
        let totalEvals = summary["total_evals"] as? Int ?? 0
        let avgScores = summary["avg_scores"] as? [String: Double] ?? [:]
        let passRates = summary["pass_rates"] as? [String: Double] ?? [:]

        let overallAvg = avgScores.values.isEmpty ? 0 : avgScores.values.reduce(0, +) / Double(avgScores.count)
        let overallPass = passRates.values.isEmpty ? 0 : passRates.values.reduce(0, +) / Double(passRates.count)

        // Session filter
        HStack {
            Text("Filter by session")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("", selection: $selectedSession) {
                Text("All Sessions").tag("all")
                ForEach(sessions, id: \.id) { s in
                    Text(String(s.id.prefix(8))).tag(s.id)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.primary)
            .onChange(of: selectedSession) { _, _ in Task { await load() } }
        }

        HStack(spacing: 12) {
            EvalCard(label: "Avg Score", value: String(format: "%.0f%%", overallAvg * 100), color: overallAvg >= 0.7 ? Theme.normal : overallAvg >= 0.5 ? Theme.elevated : Theme.high)
            EvalCard(label: "Pass Rate", value: String(format: "%.0f%%", overallPass), color: overallPass >= 70 ? Theme.normal : overallPass >= 50 ? Theme.elevated : Theme.high)
            EvalCard(label: "Total", value: "\(totalEvals)", color: Theme.primary)
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Evaluator Breakdown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.6) }
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(Theme.primary)
                }.buttonStyle(.plain)
            }

            if avgScores.isEmpty && !isLoading {
                Text("No evaluations yet - send messages to agents to generate evals")
                    .font(.caption).foregroundStyle(Theme.textTertiary).padding(.vertical, 12)
            }

            let evaluators = avgScores.keys.sorted()
            let recentEvals = summary["recent"] as? [[String: Any]] ?? []

            ForEach(evaluators, id: \.self) { name in
                let score = avgScores[name] ?? 0
                let passRate = passRates[name] ?? 0
                let passed = passRate >= 70
                let isExpanded = expandedEval == name
                let evalsForThis = recentEvals.filter { ($0["evaluator"] as? String) == name }

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            expandedEval = isExpanded ? nil : name
                        }
                    } label: {
                        HStack {
                            Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(score >= 0.7 ? Theme.normal : score >= 0.5 ? Theme.elevated : Theme.high)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(name.capitalized)
                                    .font(.caption.weight(.medium)).foregroundStyle(Theme.textPrimary)
                                Text("Pass rate: \(String(format: "%.0f%%", passRate))")
                                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", score * 100))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(score >= 0.7 ? Theme.normal : score >= 0.5 ? Theme.elevated : Theme.high)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9).weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 8) {
                            if evalsForThis.isEmpty {
                                Text("No recent evaluations")
                                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                            ForEach(Array(evalsForThis.prefix(5).enumerated()), id: \.offset) { _, eval in
                                let reason = eval["reason"] as? String ?? "No explanation"
                                let evalScore = eval["score"] as? Double ?? 0
                                let evalPassed = eval["passed"] as? Bool ?? false
                                let label = eval["label"] as? String

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(evalPassed ? Theme.normal : Theme.high)
                                            .frame(width: 5, height: 5)
                                        Text(String(format: "%.0f%%", evalScore * 100))
                                            .font(.system(size: 10).weight(.semibold).monospacedDigit())
                                            .foregroundStyle(evalPassed ? Theme.normal : Theme.high)
                                        if let lbl = label, !lbl.isEmpty {
                                            Text(lbl)
                                                .font(.system(size: 9).weight(.medium))
                                                .foregroundStyle(Theme.primary)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                    Text(reason)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                    }
                }
                if name != evaluators.last { Divider() }
            }
        }
        .padding(20)
        .card()
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        let sid = selectedSession == "all" ? nil : selectedSession
        summary = await client.fetchEvalsSummary(sessionId: sid)
        if sessions.isEmpty { await fetchSessions() }
        isLoading = false
    }

    private func fetchSessions() async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/sessions?limit=20") else { return }
        do {
            var request = URLRequest(url: url)
            APIConfig.applyAuth(to: &request)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["sessions"] as? [[String: Any]] {
                sessions = items.compactMap { s in
                    guard let id = s["session_id"] as? String else { return nil }
                    var title = s["title"] as? String ?? "Untitled"
                    if title.contains("[PATIENT CONTEXT") { title = "Chat session" }
                    if title.count > 40 { title = String(title.prefix(40)) + "..." }
                    return (id: id, title: title)
                }
            }
        } catch {}
    }
}

struct EvalCard: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .card()
    }
}

// MARK: - Metrics (Live from backend)

struct MetricsContent: View {
    @State private var metrics: [String: Any] = [:]
    @State private var isLoading = true
    @State private var sessions: [(id: String, title: String)] = []
    @State private var selectedSession: String = "all"
    private let client = ObservabilityClient()

    var body: some View {
        let totalRequests = (metrics["total_requests"] as? NSNumber)?.intValue ?? 0
        let avgLatency = (metrics["avg_latency_ms"] as? NSNumber)?.doubleValue ?? 0
        let successRate = (metrics["success_rate"] as? NSNumber)?.doubleValue ?? 0
        let totalTools = (metrics["total_tool_calls"] as? NSNumber)?.intValue ?? 0
        let agentBreakdown = (metrics["requests_by_agent"] as? [String: NSNumber])?.mapValues(\.intValue) ?? [:]
        let toolUsage = (metrics["tool_usage"] as? [String: NSNumber])?.mapValues(\.intValue) ?? [:]

        // Cost data
        let totalInputTokens = (metrics["total_input_tokens"] as? NSNumber)?.intValue ?? 0
        let totalOutputTokens = (metrics["total_output_tokens"] as? NSNumber)?.intValue ?? 0
        let totalCost = (metrics["total_cost_usd"] as? NSNumber)?.doubleValue ?? 0
        let costByModel = metrics["cost_by_model"] as? [String: Any] ?? [:]

        // Session filter
        HStack {
            Text("Filter by session")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("", selection: $selectedSession) {
                Text("All Sessions").tag("all")
                ForEach(sessions, id: \.id) { s in
                    Text(String(s.id.prefix(8))).tag(s.id)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.primary)
            .onChange(of: selectedSession) { _, _ in Task { await load() } }
        }

        HStack(spacing: 12) {
            MetricKPI(label: "Avg Response", value: String(format: "%.1fs", avgLatency / 1000), icon: "bolt.fill", color: Theme.primary)
            MetricKPI(label: "Total Queries", value: "\(totalRequests)", icon: "bubble.left.fill", color: Theme.teal)
        }
        .task { await load() }
        HStack(spacing: 12) {
            MetricKPI(label: "Success Rate", value: String(format: "%.0f%%", successRate), icon: "checkmark.seal.fill", color: Theme.normal)
            MetricKPI(label: "Tool Calls", value: "\(totalTools)", icon: "gearshape.fill", color: Theme.primary)
        }

        // Cost & Token Usage
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cost & Token Usage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: "$%.4f", totalCost))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.primary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Input Tokens")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                    Text(formatTokens(totalInputTokens))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                Divider().frame(height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output Tokens")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                    Text(formatTokens(totalOutputTokens))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                Divider().frame(height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Tokens")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                    Text(formatTokens(totalInputTokens + totalOutputTokens))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            // Cost by model breakdown
            if !costByModel.isEmpty {
                Divider()
                let models = costByModel.sorted { ($0.value as? NSNumber)?.doubleValue ?? 0 > ($1.value as? NSNumber)?.doubleValue ?? 0 }
                ForEach(models, id: \.key) { model, cost in
                    HStack {
                        Text(model)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(String(format: "$%.4f", (cost as? NSNumber)?.doubleValue ?? 0))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.teal)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(20)
        .card()

        // Agent usage
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Agent Usage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.6) }
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(Theme.primary)
                }.buttonStyle(.plain)
            }

            let agentNames = Array(agentBreakdown.keys).sorted()
            let maxCount = agentBreakdown.values.max() ?? 1

            if agentNames.isEmpty && !isLoading {
                Text("No agent usage data yet").font(.caption).foregroundStyle(Theme.textTertiary).padding(.vertical, 12)
            }

            ForEach(agentNames, id: \.self) { name in
                let count = agentBreakdown[name] ?? 0
                let pct = CGFloat(count) / CGFloat(max(1, maxCount))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name.capitalized).font(.caption.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(count) queries").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.muted).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3).fill(Theme.primary)
                                .frame(width: max(4, geo.size.width * pct), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(20)
        .card()

        // Tool usage
        if !toolUsage.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tool Usage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                let toolNames = toolUsage.sorted { $0.value > $1.value }
                ForEach(toolNames.prefix(8), id: \.key) { name, count in
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.teal)
                        Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(count)x")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.primary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(20)
            .card()
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func load() async {
        isLoading = true
        let sid = selectedSession == "all" ? nil : selectedSession
        metrics = await client.fetchMetrics(sessionId: sid)
        if sessions.isEmpty { await fetchSessions() }
        isLoading = false
    }

    private func fetchSessions() async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/sessions?limit=20") else { return }
        do {
            var request = URLRequest(url: url)
            APIConfig.applyAuth(to: &request)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["sessions"] as? [[String: Any]] {
                sessions = items.compactMap { s in
                    guard let id = s["session_id"] as? String else { return nil }
                    var title = s["title"] as? String ?? "Untitled"
                    if title.contains("[PATIENT CONTEXT") { title = "Chat session" }
                    if title.count > 40 { title = String(title.prefix(40)) + "..." }
                    return (id: id, title: title)
                }
            }
        } catch {}
    }
}

struct MetricKPI: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                Text(label).font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(16)
        .card()
    }
}

// MARK: - Observability (Live from backend)

struct ObservabilityContent: View {
    @State private var data: [String: Any] = [:]
    @State private var isLoading = true
    @State private var backendOnline = false
    private let client = ObservabilityClient()

    var body: some View {
        let services = data["services"] as? [String: String] ?? [:]
        let errorRate = data["error_rate"] as? Double ?? 0
        let avgResponse = data["avg_response_time_ms"] as? Double ?? 0
        let rpm = data["requests_per_minute"] as? Double ?? 0

        // Service health
        HStack(spacing: 12) {
            ObsStatusCard(
                label: "Agent API",
                status: backendOnline ? (services["ai_service"] ?? "healthy").capitalized : "Offline",
                color: backendOnline ? Theme.normal : Theme.high
            )
            ObsStatusCard(
                label: "Database",
                status: (services["database"] ?? "unknown").capitalized,
                color: services["database"] == "healthy" ? Theme.normal : Theme.high
            )
        }
        HStack(spacing: 12) {
            ObsStatusCard(
                label: "Agents",
                status: (services["agents"] ?? "unknown").capitalized,
                color: services["agents"] == "healthy" ? Theme.normal : Theme.elevated
            )
            ObsStatusCard(
                label: "Dexcom Share",
                status: "Active",
                color: Theme.normal
            )
        }

        // Key metrics
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("System Overview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.6) }
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(Theme.primary)
                }.buttonStyle(.plain)
            }

            let totalTraces = data["total_traces"] as? Int ?? 0
            let totalLogs = data["total_logs"] as? Int ?? 0
            let errorLogs = data["error_logs"] as? Int ?? 0

            HStack {
                ObsMetric(label: "Traces", value: "\(totalTraces)", icon: "point.topleft.down.to.point.bottomright.curvepath.fill")
                Spacer()
                ObsMetric(label: "Logs", value: "\(totalLogs)", icon: "doc.text.fill")
                Spacer()
                ObsMetric(label: "Errors", value: "\(errorLogs)", icon: "xmark.circle.fill")
                Spacer()
                ObsMetric(label: "Req/min", value: String(format: "%.1f", rpm), icon: "speedometer")
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avg Response Time")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(String(format: "%.1fs", avgResponse / 1000))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Error Rate")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(String(format: "%.1f%%", errorRate))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(errorRate > 10 ? Theme.high : Theme.normal)
                }
            }
        }
        .padding(20)
        .card()
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        backendOnline = await client.healthCheck()
        data = await client.fetchObservability()
        isLoading = false
    }
}

struct ObsStatusCard: View {
    let label: String
    let status: String
    let color: Color
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(Theme.textPrimary)
                Text(status).font(.caption2).foregroundStyle(color)
            }
            Spacer()
        }
        .padding(14)
        .card()
    }
}

struct ObsMetric: View {
    let label: String
    let value: String
    let icon: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(Theme.primary)
            Text(value).font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 9).weight(.medium)).foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Shared

struct SettingRow<Trailing: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(Theme.primary).frame(width: 20)
            Text(label).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
