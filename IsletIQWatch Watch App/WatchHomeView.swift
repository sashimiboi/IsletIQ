import SwiftUI
import WatchConnectivity

struct WatchHomeView: View {
    @Environment(WatchConnectivityManager.self) private var connectivity

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    glucoseCard
                    statsRow
                    sparklineCard
                    suppliesCard
                    quickLogCard
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("IsletIQ")
            .onAppear {
                connectivity.requestUpdate()
                connectivity.refresh()
            }
        }
    }

    // MARK: - Glucose Card

    private var glucoseCard: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(connectivity.currentGlucose)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(glucoseColor)
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: connectivity.trendSymbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(glucoseColor)
                    Text("mg/dL")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text(connectivity.status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(glucoseColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(glucoseColor.opacity(0.15), in: Capsule())

                if let update = connectivity.lastUpdate {
                    Text(update, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            WatchStat(value: "\(connectivity.tir)%", label: "TIR", color: .green)
            Divider().frame(height: 24)
            WatchStat(value: "\(connectivity.avg)", label: "Avg", color: .blue)
            Divider().frame(height: 24)
            WatchStat(value: "\(connectivity.readingCount)", label: "Rdgs", color: .teal)
        }
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Sparkline

    private var sparklineCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last 30 min")
                .font(.system(size: 9).weight(.medium))
                .foregroundStyle(.secondary)

            if connectivity.sparkline.count > 2 {
                WatchSparkline(values: connectivity.sparkline, color: glucoseColor)
                    .frame(height: 36)
            } else {
                Text("Waiting for data...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(height: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Supplies

    private var suppliesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shippingbox")
                    .font(.caption2)
                    .foregroundStyle(.teal)
                Text("Supplies")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            if connectivity.supplies.isEmpty {
                Text("No data")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(connectivity.supplies.prefix(4).enumerated()), id: \.offset) { _, supply in
                    HStack {
                        Circle()
                            .fill(supply.urgent ? Color.red : Color.green)
                            .frame(width: 5, height: 5)
                        Text(supply.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(supply.quantity)")
                            .font(.system(size: 10).weight(.semibold).monospacedDigit())
                            .foregroundStyle(supply.urgent ? .red : .primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Quick Log

    private var quickLogCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Log")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                QuickLogButton(name: "15g", icon: "pills.fill") {
                    sendQuickLog(name: "Glucose Tabs", carbs: 15)
                }
                QuickLogButton(name: "25g", icon: "leaf.fill") {
                    sendQuickLog(name: "Snack", carbs: 25)
                }
                QuickLogButton(name: "50g", icon: "fork.knife") {
                    sendQuickLog(name: "Meal", carbs: 50)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sendQuickLog(name: String, carbs: Int) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([
            "action": "log_meal",
            "name": name,
            "carbs": carbs
        ], replyHandler: nil, errorHandler: nil)
    }

    private var glucoseColor: Color {
        switch connectivity.statusColor {
        case "low": .red
        case "normal": .green
        case "elevated": .orange
        case "high": .red
        default: .blue
        }
    }
}

// MARK: - Supporting Views

struct WatchStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct QuickLogButton: View {
    let name: String
    let icon: String
    let action: () -> Void
    @State private var tapped = false

    var body: some View {
        Button(action: {
            action()
            tapped = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { tapped = false }
        }) {
            VStack(spacing: 2) {
                Image(systemName: tapped ? "checkmark" : icon)
                    .font(.system(size: 10))
                    .foregroundStyle(tapped ? .green : .teal)
                Text(name)
                    .font(.system(size: 9).weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(tapped ? Color.green.opacity(0.15) : Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct WatchSparkline: View {
    let values: [Int]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let minV = CGFloat((values.min() ?? 70) - 5)
            let maxV = CGFloat((values.max() ?? 180) + 5)
            let range = max(1, maxV - minV)

            ZStack {
                // Target zone
                let targetTop = geo.size.height - (180 - minV) / range * geo.size.height
                let targetBottom = geo.size.height - (70 - minV) / range * geo.size.height
                Rectangle()
                    .fill(Color.green.opacity(0.1))
                    .frame(height: max(0, targetBottom - targetTop))
                    .offset(y: targetTop)

                // Line
                Path { path in
                    for (i, val) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(max(1, values.count - 1))
                        let y = geo.size.height - (CGFloat(val) - minV) / range * geo.size.height
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Watch Theme (standalone, no dependency on iOS Theme)
enum Theme {
    static let primary = Color(red: 0, green: 0.2, blue: 0.63)
    static let teal = Color(red: 0.36, green: 0.7, blue: 0.8)
    static let normal = Color.green
    static let elevated = Color.orange
    static let high = Color.red
    static let textTertiary = Color.gray
}

#Preview {
    WatchHomeView()
        .environment(WatchConnectivityManager.shared)
}
