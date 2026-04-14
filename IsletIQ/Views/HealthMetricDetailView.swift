import SwiftUI

/// Reusable detail sheet for sparse / time-series HealthKit metrics
/// (heart rate, HRV, VO2 Max, blood pressure, body temperature, etc.)
struct HealthMetricDetailView: View {
    let title: String
    let icon: String
    let color: Color
    let unit: String
    let currentText: String          // pre-formatted big number
    let currentSubtitle: String?     // optional subtitle under the big number
    let series: [(date: Date, value: Double)]   // primary series
    let series2: [(date: Date, value: Double)]? // optional secondary series (e.g. diastolic for BP)
    let series2Label: String?
    let format: (Double) -> String   // value → display string
    let goodRange: ClosedRange<Double>?  // optional reference band
    let fetch: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Period = .week
    @State private var selectedIdx: Int? = nil

    enum Period: String, CaseIterable {
        case day = "1d"
        case week = "7d"
        case month = "30d"
        case quarter = "90d"
    }

    init(
        title: String,
        icon: String,
        color: Color,
        unit: String,
        currentText: String,
        currentSubtitle: String? = nil,
        series: [(date: Date, value: Double)],
        series2: [(date: Date, value: Double)]? = nil,
        series2Label: String? = nil,
        format: @escaping (Double) -> String,
        goodRange: ClosedRange<Double>? = nil,
        fetch: @escaping () async -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.unit = unit
        self.currentText = currentText
        self.currentSubtitle = currentSubtitle
        self.series = series
        self.series2 = series2
        self.series2Label = series2Label
        self.format = format
        self.goodRange = goodRange
        self.fetch = fetch
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    periodPicker
                    chartCard
                    statsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .padding(.top, 8)
            }
            .background(Theme.bg)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
            .task { await fetch() }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(currentText)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()

            Text(unit)
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)

            if let sub = currentSubtitle {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .card()
    }

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(Period.allCases, id: \.self) { p in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = p
                        selectedIdx = nil
                    }
                } label: {
                    Text(p.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(selectedTab == p ? .white : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedTab == p ? color : Theme.muted,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chart

    private var filtered: [(date: Date, value: Double)] {
        let cutoff: Date = {
            let cal = Calendar.current
            switch selectedTab {
            case .day: return cal.date(byAdding: .day, value: -1, to: .now)!
            case .week: return cal.date(byAdding: .day, value: -7, to: .now)!
            case .month: return cal.date(byAdding: .day, value: -30, to: .now)!
            case .quarter: return cal.date(byAdding: .day, value: -90, to: .now)!
            }
        }()
        return series.filter { $0.date >= cutoff }
    }

    private var filtered2: [(date: Date, value: Double)] {
        guard let s2 = series2 else { return [] }
        let cutoff: Date = {
            let cal = Calendar.current
            switch selectedTab {
            case .day: return cal.date(byAdding: .day, value: -1, to: .now)!
            case .week: return cal.date(byAdding: .day, value: -7, to: .now)!
            case .month: return cal.date(byAdding: .day, value: -30, to: .now)!
            case .quarter: return cal.date(byAdding: .day, value: -90, to: .now)!
            }
        }()
        return s2.filter { $0.date >= cutoff }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let idx = selectedIdx, idx < filtered.count {
                    let entry = filtered[idx]
                    VStack(alignment: .trailing, spacing: 1) {
                        if filtered2.isEmpty {
                            Text(format(entry.value))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(color)
                        } else if idx < filtered2.count {
                            Text("\(format(entry.value)) / \(format(filtered2[idx].value))")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(color)
                        }
                        Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundStyle(Theme.textTertiary)
                    Text("No data in this range")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
            } else {
                lineChart
                    .frame(height: 160)
            }
        }
        .padding(20)
        .card()
    }

    private struct ChartGeometry {
        let w: CGFloat
        let h: CGFloat
        let minV: Double
        let range: Double
        let minDate: Date
        let dateSpan: TimeInterval

        func point(_ entry: (date: Date, value: Double)) -> CGPoint {
            let x = w * CGFloat(entry.date.timeIntervalSince(minDate) / dateSpan)
            let y = h - h * CGFloat((entry.value - minV) / range)
            return CGPoint(x: x, y: y)
        }
    }

    private func chartGeometry(in size: CGSize) -> ChartGeometry {
        let data = filtered
        let data2 = filtered2
        var allValues = data.map(\.value)
        allValues.append(contentsOf: data2.map(\.value))
        let rawMin = allValues.min() ?? 0
        let rawMax = allValues.max() ?? 1
        let pad = max(1, (rawMax - rawMin) * 0.1)
        let minV = rawMin - pad
        let maxV = rawMax + pad
        let dates = data.map(\.date)
        let minDate = dates.min() ?? .now
        let maxDate = dates.max() ?? .now
        return ChartGeometry(
            w: size.width,
            h: size.height,
            minV: minV,
            range: max(0.0001, maxV - minV),
            minDate: minDate,
            dateSpan: max(1, maxDate.timeIntervalSince(minDate))
        )
    }

    private var lineChart: some View {
        GeometryReader { geo in
            let g = chartGeometry(in: geo.size)
            let data = filtered
            let data2 = filtered2
            let h = g.h

            ZStack(alignment: .topLeading) {
                // Good range band
                if let r = goodRange {
                    let yTop = h - h * CGFloat((r.upperBound - g.minV) / g.range)
                    let yBot = h - h * CGFloat((r.lowerBound - g.minV) / g.range)
                    Rectangle()
                        .fill(Theme.normal.opacity(0.08))
                        .frame(height: max(0, yBot - yTop))
                        .offset(y: yTop)
                }

                // Primary line
                Path { p in
                    for (i, entry) in data.enumerated() {
                        let pt = g.point(entry)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Primary dots
                ForEach(Array(data.enumerated()), id: \.offset) { _, entry in
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .position(g.point(entry))
                }

                // Secondary line (e.g. diastolic)
                if !data2.isEmpty {
                    Path { p in
                        for (i, entry) in data2.enumerated() {
                            let pt = g.point(entry)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [3, 3]))

                    ForEach(Array(data2.enumerated()), id: \.offset) { _, entry in
                        Circle()
                            .fill(color.opacity(0.5))
                            .frame(width: 3, height: 3)
                            .position(g.point(entry))
                    }
                }

                // Selection indicator
                if let idx = selectedIdx, idx < data.count {
                    let pt = g.point(data[idx])
                    Path { p in
                        p.move(to: CGPoint(x: pt.x, y: 0))
                        p.addLine(to: CGPoint(x: pt.x, y: h))
                    }
                    .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .background(Circle().fill(Theme.cardBg))
                        .frame(width: 9, height: 9)
                        .position(pt)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard !data.isEmpty else { return }
                        let target = drag.location.x
                        var bestIdx = 0
                        var bestDist = CGFloat.greatestFiniteMagnitude
                        for (i, entry) in data.enumerated() {
                            let d = abs(g.point(entry).x - target)
                            if d < bestDist { bestDist = d; bestIdx = i }
                        }
                        selectedIdx = bestIdx
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 0.2)) { selectedIdx = nil }
                        }
                    }
            )
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        let data = filtered
        let values = data.map(\.value)
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Summary (\(selectedTab.rawValue))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 0) {
                MetricStat(label: "Latest", value: data.last.map { format($0.value) } ?? "--", color: color)
                Spacer()
                MetricStat(label: "Average", value: values.isEmpty ? "--" : format(avg), color: Theme.teal)
                Spacer()
                MetricStat(label: "Min", value: values.isEmpty ? "--" : format(minV), color: Theme.normal)
                Spacer()
                MetricStat(label: "Max", value: values.isEmpty ? "--" : format(maxV), color: Theme.elevated)
            }

            Text("\(data.count) reading\(data.count == 1 ? "" : "s") • from HealthKit")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(20)
        .card()
    }
}

private struct MetricStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
