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
                    pumpCard
                    sleepCard
                    recentReadingsCard
                    recentMealsCard
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

    // MARK: - Pump Card

    private var pumpCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "drop.circle")
                    .font(.caption2)
                    .foregroundStyle(Theme.primary)
                Text(connectivity.pumpModel)
                    .font(.caption2.weight(.semibold))
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "battery.75")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                    Text("\(connectivity.pumpBattery)%")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", connectivity.basalRate))
                        .font(.system(size: 12).weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.primary)
                    Text("u/hr")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 20)

                VStack(spacing: 2) {
                    Text(String(format: "%.1f", connectivity.lastBolus))
                        .font(.system(size: 12).weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.teal)
                    Text("last bolus")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 20)

                VStack(spacing: 2) {
                    Text("\(Int(connectivity.reservoir))")
                        .font(.system(size: 12).weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("units")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Recent boluses
            if !connectivity.recentBoluses.isEmpty {
                Divider()
                ForEach(Array(connectivity.recentBoluses.prefix(3).enumerated()), id: \.offset) { _, bolus in
                    HStack {
                        Image(systemName: "syringe.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.primary)
                        Text(String(format: "%.1fu", bolus.units))
                            .font(.system(size: 10).weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        if bolus.carbs > 0 {
                            Text("\(bolus.carbs)g")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.teal)
                        }
                        Spacer()
                        Text(Date(timeIntervalSince1970: bolus.timestamp), format: .dateTime.hour().minute())
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Sleep Card

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "moon.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text("Sleep")
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text(String(format: "%.1fh", connectivity.sleepHours))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.purple)
            }

            if !connectivity.sleepSegments.isEmpty {
                // Mini sleep stages chart
                WatchSleepChart(segments: connectivity.sleepSegments)
                    .frame(height: 40)

                // Stage breakdown
                VStack(spacing: 3) {
                    WatchSleepRow(color: Color(red: 0.9, green: 0.35, blue: 0.3), label: "Awake", minutes: connectivity.awakeMin)
                    WatchSleepRow(color: Color(red: 0.45, green: 0.65, blue: 0.9), label: "REM", minutes: connectivity.remMin)
                    WatchSleepRow(color: Color(red: 0.2, green: 0.4, blue: 0.85), label: "Core", minutes: connectivity.coreMin)
                    WatchSleepRow(color: Color(red: 0.35, green: 0.3, blue: 0.75), label: "Deep", minutes: connectivity.deepMin)
                }
            } else {
                Text("No sleep data")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Recent Readings

    private var recentReadingsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                    .foregroundStyle(.teal)
                Text("Recent")
                    .font(.caption2.weight(.semibold))
            }

            if connectivity.sparkline.count > 1 {
                ForEach(Array(connectivity.sparkline.suffix(5).reversed().enumerated()), id: \.offset) { i, value in
                    HStack {
                        let color: Color = value < 70 ? .red : value <= 180 ? .green : value <= 250 ? .orange : .red
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                        Text("\(value)")
                            .font(.system(size: 11).weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("mg/dL")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(i * 5)m ago")
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Waiting for data...")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Recent Meals

    private var recentMealsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "fork.knife")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Meals")
                    .font(.caption2.weight(.semibold))
            }

            if connectivity.recentMeals.isEmpty {
                Text("No meals today")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(connectivity.recentMeals.prefix(4).enumerated()), id: \.offset) { _, meal in
                    HStack {
                        Text(meal.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(meal.carbs)g")
                            .font(.system(size: 10).weight(.semibold).monospacedDigit())
                            .foregroundStyle(.teal)
                    }
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

// MARK: - Watch Sleep Chart (mini, with connecting lines)

struct WatchSleepChart: View {
    let segments: [(stage: String, start: Double, end: Double, minutes: Double)]

    private let stageColors: [String: Color] = [
        "Awake": Color(red: 0.9, green: 0.35, blue: 0.3),
        "REM": Color(red: 0.45, green: 0.65, blue: 0.9),
        "Core": Color(red: 0.2, green: 0.4, blue: 0.85),
        "Deep": Color(red: 0.35, green: 0.3, blue: 0.75),
    ]

    private let stageDepth: [String: Int] = ["Awake": 0, "REM": 1, "Core": 2, "Deep": 3]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let rowH = h / 4.0

            guard let minTime = segments.map(\.start).min(),
                  let maxTime = segments.map(\.end).max() else { return AnyView(EmptyView()) }
            let timeRange = max(1, maxTime - minTime)

            return AnyView(
                ZStack(alignment: .topLeading) {
                    // Stage blocks only
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        let x1 = w * CGFloat((seg.start - minTime) / timeRange)
                        let x2 = w * CGFloat((seg.end - minTime) / timeRange)
                        let segW = max(2, x2 - x1)
                        let depth = stageDepth[seg.stage] ?? 2
                        let yCenter = rowH * CGFloat(depth) + rowH / 2

                        RoundedRectangle(cornerRadius: 2)
                            .fill(stageColors[seg.stage] ?? .blue)
                            .frame(width: segW, height: rowH * 0.65)
                            .position(x: x1 + segW / 2, y: yCenter)
                    }
                }
            )
        }
    }
}

struct WatchSleepRow: View {
    let color: Color
    let label: String
    let minutes: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.primary)
            Spacer()
            Text(formatMin(minutes))
                .font(.system(size: 9).weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func formatMin(_ m: Double) -> String {
        let hrs = Int(m) / 60
        let mins = Int(m) % 60
        if hrs > 0 { return "\(hrs)h \(mins)m" }
        return "\(mins)m"
    }
}

#Preview {
    WatchHomeView()
        .environment(WatchConnectivityManager.shared)
}
