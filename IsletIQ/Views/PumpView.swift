import SwiftUI

struct PumpView: View {
    var healthKit: HealthKitManager?
    @State private var backendPump: BackendPumpData?
    @State private var isLoading = true

    struct BackendPumpData {
        let basalRate: Double
        let lastBolus: Double
        let totalBasal: Double
        let totalBolus: Double
        let dailyTotal: Double
        let source: String
        let recentBoluses: [(units: Double, carbs: Int, timestamp: Date)]
    }

    // Omnipod 5 does not write to HealthKit — always use backend (Glooko data)
    private var useHealthKit: Bool { false }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                deviceCard
                deliveryCard
                reservoirCard
                bolusHistoryCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .navigationTitle("Pump")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await loadBackendFallback() }
    }

    private func loadBackendFallback() async {
        defer { isLoading = false }
        guard let url = URL(string: "\(APIConfig.baseURL)/api/pump/latest") else { return }
        var request = URLRequest(url: url)
        APIConfig.applyAuth(to: &request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let boluses = (json["recentBoluses"] as? [[String: Any]])?.map { b in
                    (units: (b["units"] as? NSNumber)?.doubleValue ?? 0,
                     carbs: (b["carbs"] as? NSNumber)?.intValue ?? 0,
                     timestamp: Date(timeIntervalSince1970: (b["timestamp"] as? NSNumber)?.doubleValue ?? 0))
                } ?? []
                await MainActor.run {
                    backendPump = BackendPumpData(
                        basalRate: (json["basalRate"] as? NSNumber)?.doubleValue ?? 0,
                        lastBolus: (json["lastBolus"] as? NSNumber)?.doubleValue ?? 0,
                        totalBasal: (json["totalBasal"] as? NSNumber)?.doubleValue ?? 0,
                        totalBolus: (json["totalBolus"] as? NSNumber)?.doubleValue ?? 0,
                        dailyTotal: (json["dailyTotal"] as? NSNumber)?.doubleValue ?? 0,
                        source: json["source"] as? String ?? "healthkit",
                        recentBoluses: boluses
                    )
                }
            }
        } catch {}
    }

    // MARK: - Computed props (HealthKit first, backend fallback)

    private var basalRate: Double { useHealthKit ? (healthKit?.basalRateEstimate ?? 0) : (backendPump?.basalRate ?? 0) }
    private var lastBolusUnits: Double { useHealthKit ? (healthKit?.lastBolusUnits ?? 0) : (backendPump?.lastBolus ?? 0) }
    private var dailyTotal: Double { useHealthKit ? (healthKit?.totalBasalToday ?? 0) + (healthKit?.totalBolusToday ?? 0) : (backendPump?.dailyTotal ?? 0) }
    private var dataSource: String { useHealthKit ? "HealthKit" : (backendPump?.source ?? "—") }

    // MARK: - Cards

    private var deviceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.primary.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: "medical.thermometer.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Omnipod 5")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Circle().fill(hasData ? Theme.normal : Theme.textTertiary).frame(width: 6, height: 6)
                    Text(hasData ? "Data from \(dataSource)" : (isLoading ? "Loading..." : "No data"))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(20)
        .card()
    }

    private var deliveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Insulin Delivery")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 0) {
                DeliveryItem(label: "Basal Rate", value: "\(String(format: "%.2f", basalRate)) u/hr", icon: "waveform.path", color: Theme.primary)
                Divider().frame(height: 40).padding(.horizontal, 8)
                DeliveryItem(label: "Last Bolus", value: String(format: "%.1f u", lastBolusUnits), icon: "drop.fill", color: Theme.teal)
                Divider().frame(height: 40).padding(.horizontal, 8)
                DeliveryItem(label: "Daily Total", value: String(format: "%.1f u", dailyTotal), icon: "chart.bar.fill", color: Theme.primary)
            }
        }
        .padding(20)
        .card()
    }

    private var reservoirCard: some View {
        let maxUnits = 200.0
        let remaining = max(0, maxUnits - dailyTotal)
        let daysLeft = dailyTotal > 0 ? remaining / dailyTotal : 0

        return VStack(alignment: .leading, spacing: 14) {
            Text("Reservoir (estimated)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Theme.border, lineWidth: 6)
                        .frame(width: 60, height: 60)
                    Circle()
                        .trim(from: 0, to: remaining / maxUnits)
                        .stroke(Theme.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(remaining))")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("~\(Int(remaining)) of \(Int(maxUnits)) units")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if daysLeft > 0 {
                        Text("Est. ~\(String(format: "%.1f", daysLeft)) days remaining")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()
            }
        }
        .padding(20)
        .card()
    }

    private var bolusHistoryCard: some View {
        let hkBoluses = healthKit?.recentBoluses.prefix(6).map { b in
            (units: b.units, carbs: 0, timestamp: b.date)
        } ?? []
        let boluses = useHealthKit ? Array(hkBoluses) : (backendPump?.recentBoluses.prefix(6).map { $0 } ?? [])

        return VStack(alignment: .leading, spacing: 10) {
            Text("Recent Boluses")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            if boluses.isEmpty && !isLoading {
                Text("No boluses available")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 8)
            } else if isLoading && boluses.isEmpty {
                ProgressView()
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(boluses.enumerated()), id: \.offset) { i, bolus in
                    HStack {
                        Image(systemName: "syringe.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.teal)
                            .frame(width: 16)
                        Text(String(format: "%.1f u", bolus.units))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        if bolus.carbs > 0 {
                            Text("\(bolus.carbs)g")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.primary.opacity(0.08), in: Capsule())
                        }
                        Spacer()
                        Text(bolus.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 3)
                    if i < boluses.count - 1 { Divider() }
                }
            }
        }
        .padding(20)
        .card()
    }

    private var hasData: Bool { dailyTotal > 0 || backendPump != nil }
}

struct DeliveryItem: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 10).weight(.medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
