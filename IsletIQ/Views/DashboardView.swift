import SwiftUI
import SwiftData

// Simple struct for chart/list data (not SwiftData)
struct ReadingPoint: Identifiable {
    let id = UUID()
    let value: Int
    let timestamp: Date
    let trend: TrendArrow

    var status: GlucoseStatus {
        if value < 70 { return .low }
        if value <= 140 { return .normal }
        if value <= 180 { return .elevated }
        return .high
    }
}

enum ChartRange: String, CaseIterable {
    case threeHr = "3h"
    case day = "24h"
    case threeDays = "3d"
    case week = "7d"
    case twoWeeks = "14d"
    case month = "30d"

    var seconds: TimeInterval {
        switch self {
        case .threeHr: 3 * 3600
        case .day: 86400
        case .threeDays: 3 * 86400
        case .week: 7 * 86400
        case .twoWeeks: 14 * 86400
        case .month: 30 * 86400
        }
    }
}

struct DashboardView: View {
    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var storedReadings: [GlucoseReading]
    var dexcomManager: DexcomManager?
    @State private var chartRange: ChartRange = .day
    @State private var chartMode: ChartMode = .trend
    @State private var agpRange: ChartRange = .week
    @State private var recentMode: RecentMode = .cgm

    enum RecentMode: String, CaseIterable {
        case cgm = "CGM"
        case pump = "Pump"
    }

    enum ChartMode: String, CaseIterable {
        case trend = "Trend"
        case agp = "AGP"
    }

    // Unified data source — live Dexcom if available, else stored
    private var allReadings: [ReadingPoint] {
        if let mgr = dexcomManager, !mgr.liveReadings.isEmpty {
            return mgr.liveReadings.compactMap { r in
                guard let ts = r.timestamp else { return nil }
                return ReadingPoint(value: r.safeValue, timestamp: ts, trend: r.trendArrow)
            }.sorted { $0.timestamp > $1.timestamp }
        }
        return storedReadings.map {
            ReadingPoint(value: $0.value, timestamp: $0.timestamp, trend: $0.trendArrow)
        }
    }

    private var latest: ReadingPoint? { allReadings.first }

    private var todayReadings: [ReadingPoint] {
        let start = Calendar.current.startOfDay(for: .now)
        return allReadings.filter { $0.timestamp >= start }
    }

    private var timeInRange: Int {
        guard !todayReadings.isEmpty else { return 0 }
        let inRange = todayReadings.filter { $0.value >= 70 && $0.value <= 180 }.count
        return Int(Double(inRange) / Double(todayReadings.count) * 100)
    }

    private var avgToday: Int {
        guard !todayReadings.isEmpty else { return 0 }
        return todayReadings.map(\.value).reduce(0, +) / todayReadings.count
    }

    private var isLive: Bool { dexcomManager?.isLoggedIn == true && !(dexcomManager?.liveReadings.isEmpty ?? true) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                cgmCard
                pumpStatusCard
                glucoseChartCard
                statsRow
                distributionCard
                recentReadingsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .navigationTitle("Hi, Anthony")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .tint(Theme.primary)
        .refreshable {
            if let mgr = dexcomManager {
                await mgr.fetchLatest()
            }
        }
    }

    // MARK: - CGM Card

    private var cgmCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(isLive ? Theme.normal : Theme.elevated).frame(width: 7, height: 7)
                    Text(isLive ? "Dexcom G7 Live" : "CGM - Offline")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    if isLive, let sync = dexcomManager?.lastSync {
                        Text("· \(sync, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                if let r = latest {
                    let color = Theme.statusColor(r.status)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(r.value)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                        VStack(alignment: .leading, spacing: 2) {
                            Image(systemName: r.trend.symbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(color)
                            Text("mg/dL")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    HStack(spacing: 8) {
                        StatusBadge(label: r.status.label, color: color)
                        Text(r.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                } else {
                    Text("--")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }

                // Sensor days remaining
                HStack(spacing: 6) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .foregroundStyle(Theme.teal)
                        .font(.caption2)
                    Text("\(MockData.cgmModel) · \(MockData.sensorDaysRemaining)d left")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            // Sparkline from last 30 min
            let spark = Array(allReadings.prefix(6).reversed())
            if spark.count > 2 {
                MiniSparkline(points: spark)
                    .frame(width: 80, height: 44)
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        let rangeVals = rangeReadings.map(\.value)
        let rangeTIR: Int = {
            guard !rangeVals.isEmpty else { return 0 }
            let inRange = rangeVals.filter { $0 >= 70 && $0 <= 180 }.count
            return Int(Double(inRange) / Double(rangeVals.count) * 100)
        }()
        let rangeAvg: Int = rangeVals.isEmpty ? 0 : rangeVals.reduce(0, +) / rangeVals.count

        return HStack(spacing: 12) {
            StatBox(icon: "target", label: "TIR", value: "\(rangeTIR)%", color: Theme.normal)
            StatBox(icon: "chart.bar.fill", label: "Avg", value: "\(rangeAvg)", color: Theme.primary)
            StatBox(icon: "number", label: "Readings", value: "\(rangeReadings.count)", color: Theme.teal)
        }
    }

    // MARK: - Pump Status

    private var pumpStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pump Status")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(MockData.pumpModel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.primary.opacity(0.08), in: Capsule())
            }

            HStack(spacing: 20) {
                PumpStat(icon: "waveform.path", label: "Basal", value: "\(MockData.activeBasalRate) u/hr")
                Divider().frame(height: 32)
                PumpStat(icon: "syringe.fill", label: "Last Bolus", value: "\(MockData.lastBolus)u")
                Divider().frame(height: 32)
                PumpStat(icon: "cylinder.fill", label: "Reservoir", value: "\(Int(MockData.reservoirUnits))u")
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "battery.75")
                        .foregroundStyle(Theme.normal)
                        .font(.caption)
                    Text("\(MockData.pumpBattery)%")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Glucose Chart

    private var rangeReadings: [ReadingPoint] {
        let cutoff = Date().addingTimeInterval(-chartRange.seconds)
        return allReadings.filter { $0.timestamp >= cutoff }
    }

    private var bolusPointsForRange: [BolusPoint] {
        let cutoff = Date().addingTimeInterval(-chartRange.seconds)
        return MockData.bolusData()
            .filter { $0.timestamp >= cutoff }
            .map { BolusPoint(timestamp: $0.timestamp, units: $0.insulinDelivered, carbs: $0.carbs) }
    }

    private var glucoseChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Glucose Trend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isLive {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.normal).frame(width: 5, height: 5)
                        Text("Live")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.normal)
                    }
                }
            }

            // Chart mode + range filter
            HStack(spacing: 6) {
                // Mode toggle
                ForEach(ChartMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { chartMode = mode }
                    } label: {
                        Text(mode.rawValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(chartMode == mode ? .white : Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                chartMode == mode ? Theme.primary : Theme.muted,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 16)

                // Range pills
                if chartMode == .trend {
                    ForEach(ChartRange.allCases, id: \.self) { range in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { chartRange = range }
                        } label: {
                            Text(range.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(chartRange == range ? .white : Theme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    chartRange == range ? Theme.primary.opacity(0.7) : Theme.muted,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(ChartRange.allCases, id: \.self) { range in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { agpRange = range }
                        } label: {
                            Text(range.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(agpRange == range ? .white : Theme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    agpRange == range ? Theme.primary.opacity(0.7) : Theme.muted,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }

            let chartData = Array(rangeReadings.sorted { $0.timestamp < $1.timestamp })

            if chartMode == .agp {
                // AGP uses stored readings filtered by selected range
                AGPChartView(readings: allReadings, agpRange: agpRange)
                    .frame(height: 200)

                HStack(spacing: 10) {
                    ChartLegend(color: Color(red: 0.1, green: 0.15, blue: 0.45), label: "Median")
                    ChartLegend(color: Color(red: 0.35, green: 0.5, blue: 0.85).opacity(0.3), label: "25-75%")
                    ChartLegend(color: Color(red: 0.35, green: 0.5, blue: 0.85).opacity(0.15), label: "10-90%")
                    ChartLegend(color: Color(red: 0.35, green: 0.5, blue: 0.85).opacity(0.4), label: "Min/Max")
                    ChartLegend(color: .green.opacity(0.5), label: "Target")
                }
            } else if chartData.isEmpty {
                Text("No data available")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                let bolusData = bolusPointsForRange
                StackedChartView(glucosePoints: chartData, bolusPoints: bolusData)
                    .frame(height: 240)

                HStack(spacing: 12) {
                    ChartLegend(color: Theme.primary, label: "Glucose")
                    ChartLegend(color: Theme.teal.opacity(0.5), label: "Insulin")
                    ChartLegend(color: Theme.teal.opacity(0.3), label: "Carbs")
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Distribution

    private var distributionCard: some View {
        let vals = rangeReadings.map(\.value)
        let lowCount = vals.filter { $0 < 70 }.count
        let inRangeCount = vals.filter { $0 >= 70 && $0 <= 180 }.count
        let highCount = vals.filter { $0 > 180 }.count
        let total = max(1, vals.count)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Time in Range")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            GeometryReader { geo in
                HStack(spacing: 2) {
                    if lowCount > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.low)
                            .frame(width: max(4, geo.size.width * CGFloat(lowCount) / CGFloat(total)))
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.normal)
                        .frame(width: max(4, geo.size.width * CGFloat(inRangeCount) / CGFloat(total)))
                    if highCount > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.elevated)
                            .frame(width: max(4, geo.size.width * CGFloat(highCount) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 24)

            HStack {
                DistStat(label: "Low", pct: "\(lowCount * 100 / total)%", count: "\(lowCount)", color: Theme.low)
                Spacer()
                DistStat(label: "In Range", pct: "\(inRangeCount * 100 / total)%", count: "\(inRangeCount)", color: Theme.normal)
                Spacer()
                DistStat(label: "High", pct: "\(highCount * 100 / total)%", count: "\(highCount)", color: Theme.elevated)
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Recent Readings (from live data)

    private var recentReadingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                // CGM / Pump toggle
                HStack(spacing: 0) {
                    ForEach(RecentMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { recentMode = mode }
                        } label: {
                            Text(mode.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(recentMode == mode ? .white : Theme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    recentMode == mode ? Theme.primary : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer()
                if isLive && recentMode == .cgm {
                    Text("Live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.normal)
                }
            }

            if recentMode == .cgm {
                let recent = Array(allReadings.prefix(8))
                if recent.isEmpty {
                    Text("No readings")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { i, reading in
                        LiveReadingRow(reading: reading)
                        if i < recent.count - 1 {
                            Divider()
                        }
                    }
                }
            } else {
                let recentBolus = MockData.bolusData()
                    .sorted { $0.timestamp > $1.timestamp }
                    .prefix(8)

                if recentBolus.isEmpty {
                    Text("No pump data")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(Array(recentBolus.enumerated()), id: \.offset) { i, bolus in
                        HStack(spacing: 8) {
                            Image(systemName: "syringe.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.primary)
                                .frame(width: 16)
                            Text(String(format: "%.1fu", bolus.insulinDelivered))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                            if bolus.carbs > 0 {
                                Text("\(bolus.carbs)g carbs")
                                    .font(.caption)
                                    .foregroundStyle(Theme.teal)
                            }
                            Spacer()
                            Text(bolus.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 2)
                        if i < recentBolus.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(20)
        .card()
    }
}

// MARK: - Live Reading Row

struct LiveReadingRow: View {
    let reading: ReadingPoint
    private var color: Color { Theme.statusColor(reading.status) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: reading.trend.symbol)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            Text("\(reading.value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text("mg/dL")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(reading.timestamp, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
            Text(reading.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Interactive Chart

struct LiveChartView: View {
    let points: [ReadingPoint]
    @State private var selectedIndex: Int? = nil
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let minVal = max(40, (points.map(\.value).min() ?? 70) - 15)
            let maxVal = min(350, (points.map(\.value).max() ?? 180) + 15)
            let range = CGFloat(maxVal - minVal)
            let w = geo.size.width
            let h = geo.size.height
            let chartL: CGFloat = 30
            let chartW = w - chartL - 4

            let minTime = points.first?.timestamp.timeIntervalSince1970 ?? 0
            let maxTime = points.last?.timestamp.timeIntervalSince1970 ?? 1
            let timeRange = max(1, maxTime - minTime)

            ZStack(alignment: .topLeading) {
                // Y-axis grid
                ForEach([70, 120, 180, 250], id: \.self) { line in
                    if line >= minVal && line <= maxVal {
                        let y = h - (CGFloat(line - minVal) / range) * h
                        Path { p in
                            p.move(to: CGPoint(x: chartL, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Theme.border, style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        Text("\(line)")
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .position(x: 13, y: y)
                    }
                }

                // Low zone
                let lowZoneY = h - (CGFloat(70 - minVal) / range) * h
                if 70 > minVal {
                    Rectangle()
                        .fill(Theme.low.opacity(0.06))
                        .frame(width: chartW, height: max(0, h - lowZoneY))
                        .offset(x: chartL, y: lowZoneY)
                }

                // Target range
                let targetTop = h - (CGFloat(180 - minVal) / range) * h
                let targetBottom = h - (CGFloat(70 - minVal) / range) * h
                Rectangle()
                    .fill(Theme.normal.opacity(0.08))
                    .frame(width: chartW, height: max(0, targetBottom - targetTop))
                    .offset(x: chartL, y: targetTop)

                // High zone
                if 180 < maxVal {
                    let highTop = h - (CGFloat(min(maxVal, 350) - minVal) / range) * h
                    Rectangle()
                        .fill(Theme.high.opacity(0.05))
                        .frame(width: chartW, height: max(0, targetTop - highTop))
                        .offset(x: chartL, y: highTop)
                }

                // Target lines
                Path { p in
                    let y70 = h - (CGFloat(70 - minVal) / range) * h
                    p.move(to: CGPoint(x: chartL, y: y70))
                    p.addLine(to: CGPoint(x: w, y: y70))
                }
                .stroke(Theme.low.opacity(0.4), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))

                Path { p in
                    let y180 = h - (CGFloat(180 - minVal) / range) * h
                    p.move(to: CGPoint(x: chartL, y: y180))
                    p.addLine(to: CGPoint(x: w, y: y180))
                }
                .stroke(Theme.high.opacity(0.4), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))

                // Gradient fill
                Path { path in
                    for (i, pt) in points.enumerated() {
                        let x = chartL + chartW * CGFloat(pt.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange)
                        let y = h - (CGFloat(pt.value - minVal) / range) * h
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: chartL + chartW * CGFloat(last.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange), y: h))
                    }
                    if let first = points.first {
                        path.addLine(to: CGPoint(x: chartL + chartW * CGFloat(first.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange), y: h))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Theme.primary.opacity(isDragging ? 0.08 : 0.15), Theme.primary.opacity(0.03), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                // Single consistent line (STD: one color, let zones tell the story)
                Path { path in
                    var started = false
                    for (i, pt) in points.enumerated() {
                        let x = chartL + chartW * CGFloat(pt.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange)
                        let y = h - (CGFloat(pt.value - minVal) / range) * h

                        // Break line at gaps > 15 min
                        if i > 0 {
                            let gap = pt.timestamp.timeIntervalSince(points[i-1].timestamp)
                            if gap > 900 {
                                started = false
                            }
                        }

                        if !started {
                            path.move(to: CGPoint(x: x, y: y))
                            started = true
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Selected point indicator + scrubber line
                if let idx = selectedIndex, idx < points.count {
                    let pt = points[idx]
                    let sx = chartL + chartW * CGFloat(pt.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange)
                    let sy = h - (CGFloat(pt.value - minVal) / range) * h
                    let color = Theme.statusColor(pt.status)

                    // Vertical scrubber line
                    Path { p in
                        p.move(to: CGPoint(x: sx, y: 0))
                        p.addLine(to: CGPoint(x: sx, y: h))
                    }
                    .stroke(Theme.textTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Dot
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Theme.cardBg, lineWidth: 2.5))
                        .shadow(color: color.opacity(0.4), radius: 4)
                        .position(x: sx, y: sy)

                    // Tooltip
                    ChartTooltip(point: pt)
                        .position(
                            x: min(max(sx, 70), w - 70),
                            y: max(sy - 40, 24)
                        )
                }

                // Latest point (when not scrubbing)
                if selectedIndex == nil, let last = points.last {
                    let lx = chartL + chartW * CGFloat(last.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange)
                    let ly = h - (CGFloat(last.value - minVal) / range) * h
                    let color = Theme.statusColor(last.status)

                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.cardBg, lineWidth: 2))
                        .shadow(color: color.opacity(0.4), radius: 4)
                        .position(x: lx, y: ly)
                }

                // X-axis time labels
                let labelCount = 5
                ForEach(0..<labelCount, id: \.self) { i in
                    let t = minTime + timeRange * Double(i) / Double(labelCount - 1)
                    let x = chartL + chartW * CGFloat(i) / CGFloat(labelCount - 1)
                    Text(Date(timeIntervalSince1970: t), format: .dateTime.hour().minute())
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                        .position(x: x, y: h + 10)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let xPos = drag.location.x - chartL
                        let pct = max(0, min(1, xPos / chartW))
                        let targetTime = minTime + Double(pct) * timeRange
                        // Find nearest point
                        var nearest = 0
                        var nearestDist = Double.infinity
                        for (i, pt) in points.enumerated() {
                            let dist = abs(pt.timestamp.timeIntervalSince1970 - targetTime)
                            if dist < nearestDist {
                                nearestDist = dist
                                nearest = i
                            }
                        }
                        selectedIndex = nearest
                    }
                    .onEnded { _ in
                        isDragging = false
                        // Keep tooltip visible briefly
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedIndex = nil
                            }
                        }
                    }
            )
        }
        .padding(.bottom, 14)
    }
}

// MARK: - Chart Tooltip

struct ChartTooltip: View {
    let point: ReadingPoint
    private var color: Color { Theme.statusColor(point.status) }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(point.value) mg/dL")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(point.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 3) {
                Image(systemName: point.trend.symbol)
                    .font(.system(size: 8))
                Text(point.status.label)
                    .font(.system(size: 9).weight(.medium))
            }
            .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

// MARK: - Mini Sparkline

struct MiniSparkline: View {
    let points: [ReadingPoint]

    var body: some View {
        GeometryReader { geo in
            let vals = points.map(\.value)
            let minV = CGFloat((vals.min() ?? 70) - 5)
            let maxV = CGFloat((vals.max() ?? 180) + 5)
            let range = max(1, maxV - minV)
            Path { path in
                for (i, pt) in points.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(max(1, points.count - 1))
                    let y = geo.size.height - (CGFloat(pt.value) - minV) / range * geo.size.height
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Theme.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Supporting Views

struct StatusBadge: View {
    let label: String
    let color: Color
    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.pillRadius, style: .continuous))
    }
}

struct StatBox: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 6) {
            IconBox(icon: icon, color: color, size: 28)
            Text(value).font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .card()
    }
}

struct PumpStat: View {
    let icon: String
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            IconBox(icon: icon, color: Theme.accent, size: 24)
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 10).weight(.medium)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ChartLegend: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 8, height: 4)
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
        }
    }
}

struct DistStat: View {
    let label: String
    let pct: String
    let count: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(pct).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .modelContainer(for: GlucoseReading.self, inMemory: true)
}
