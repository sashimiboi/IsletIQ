import SwiftUI

// Bolus data point
struct BolusPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let units: Double
    let carbs: Int
}

struct StackedChartView: View {
    let glucosePoints: [ReadingPoint]
    let bolusPoints: [BolusPoint]
    let basalRate: Double = 0.5 // u/hr from Omnipod 5

    @State private var selectedGlucoseIndex: Int? = nil
    @State private var isDragging = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0

    // Layout constants
    private let chartL: CGFloat = 28  // left y-axis space
    private let chartR: CGFloat = 28  // right y-axis space

    var body: some View {
        GeometryReader { outerGeo in
            let baseW = outerGeo.size.width
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    mainChart
                        .frame(width: baseW * zoomScale, height: 220)
                        .clipped()
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            zoomScale = max(1.0, min(4.0, lastZoomScale * scale))
                        }
                        .onEnded { scale in
                            zoomScale = max(1.0, min(4.0, lastZoomScale * scale))
                            lastZoomScale = zoomScale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.3)) {
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                    }
                }

                timeAxis
                    .frame(height: 16)
            }
        }
    }

    // Time range - use both glucose and bolus points
    private var minTime: TimeInterval {
        let gMin = glucosePoints.first?.timestamp.timeIntervalSince1970 ?? 0
        let bMin = bolusPoints.map(\.timestamp.timeIntervalSince1970).min() ?? gMin
        return min(gMin, bMin)
    }
    private var maxTime: TimeInterval {
        let gMax = glucosePoints.last?.timestamp.timeIntervalSince1970 ?? 1
        let bMax = bolusPoints.map(\.timestamp.timeIntervalSince1970).max() ?? gMax
        return max(gMax, bMax)
    }
    private var timeRange: TimeInterval {
        max(300, maxTime - minTime)
    }

    // Insulin y-axis scale
    private var maxBolus: Double {
        let m = bolusPoints.map(\.units).max() ?? 10
        return max(2, ceil(m / 2) * 2) // round up to nearest even number
    }

    // MARK: - Unified Chart

    private var mainChart: some View {
        GeometryReader { geo in
            let minVal = max(40, (glucosePoints.map(\.value).min() ?? 70) - 15)
            let maxVal = min(350, (glucosePoints.map(\.value).max() ?? 180) + 15)
            let gRange = CGFloat(maxVal - minVal)
            let w = geo.size.width
            let h = geo.size.height
            let chartW = w - chartL - chartR
            // Insulin bars occupy bottom 35% of chart
            let insulinZoneH = h * 0.35

            ZStack(alignment: .topLeading) {
                // --- Left Y-axis (Glucose) ---
                ForEach([70, 180, 250], id: \.self) { line in
                    if line >= minVal && line <= maxVal {
                        let y = h - (CGFloat(line - minVal) / gRange) * h
                        Text("\(line)")
                            .font(.system(size: 7).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .position(x: 12, y: y)
                    }
                }

                // --- Right Y-axis (Insulin) ---
                if !bolusPoints.isEmpty {
                    let steps = insulinYSteps
                    ForEach(steps, id: \.self) { units in
                        let y = h - (CGFloat(units) / CGFloat(maxBolus)) * insulinZoneH
                        Text(String(format: "%.0f", units))
                            .font(.system(size: 7).monospacedDigit())
                            .foregroundStyle(Theme.teal.opacity(0.6))
                            .position(x: w - 10, y: y)
                    }
                    // "u" label at top of insulin axis
                    Text("u")
                        .font(.system(size: 6).weight(.medium))
                        .foregroundStyle(Theme.teal.opacity(0.5))
                        .position(x: w - 10, y: h - insulinZoneH - 8)
                }

                // --- High zone fill (above 180) ---
                if 180 >= minVal && 180 <= maxVal {
                    let highY = h - (CGFloat(180 - minVal) / gRange) * h
                    Rectangle()
                        .fill(Theme.high.opacity(0.06))
                        .frame(width: chartW, height: max(0, highY))
                        .offset(x: chartL, y: 0)
                }

                // --- Target range (70-180) ---
                let targetTop = h - (CGFloat(180 - minVal) / gRange) * h
                let targetBottom = h - (CGFloat(70 - minVal) / gRange) * h
                Rectangle()
                    .fill(Theme.normal.opacity(0.06))
                    .frame(width: chartW, height: max(0, targetBottom - targetTop))
                    .offset(x: chartL, y: targetTop)

                // --- Low zone fill (below 70) ---
                if 70 >= minVal && 70 <= maxVal {
                    let lowY = h - (CGFloat(70 - minVal) / gRange) * h
                    Rectangle()
                        .fill(Theme.low.opacity(0.08))
                        .frame(width: chartW, height: max(0, h - lowY))
                        .offset(x: chartL, y: lowY)
                }

                // Target lines
                ForEach([70, 180], id: \.self) { line in
                    if line >= minVal && line <= maxVal {
                        let y = h - (CGFloat(line - minVal) / gRange) * h
                        Path { p in
                            p.move(to: CGPoint(x: chartL, y: y))
                            p.addLine(to: CGPoint(x: chartL + chartW, y: y))
                        }
                        .stroke(
                            line == 70 ? Theme.low.opacity(0.25) : Theme.high.opacity(0.25),
                            style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                        )
                    }
                }

                // --- Insulin lollipops (behind glucose line) ---
                if !bolusPoints.isEmpty {
                    ForEach(bolusPoints) { bolus in
                        let x = chartL + chartW * CGFloat(bolus.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange)
                        let stemH = max(6, insulinZoneH * CGFloat(bolus.units / maxBolus))

                        if x >= chartL && x <= chartL + chartW {
                            // Thin stem from bottom
                            Path { p in
                                p.move(to: CGPoint(x: x, y: h))
                                p.addLine(to: CGPoint(x: x, y: h - stemH))
                            }
                            .stroke(Theme.teal.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                            // Dot at top of stem
                            Circle()
                                .fill(Theme.teal.opacity(0.6))
                                .frame(width: 5, height: 5)
                                .position(x: x, y: h - stemH)

                            // Unit label above dot for significant doses
                            if bolus.units >= 3 {
                                Text(String(format: "%.0f", bolus.units))
                                    .font(.system(size: 7).weight(.medium).monospacedDigit())
                                    .foregroundStyle(Theme.teal.opacity(0.8))
                                    .position(x: x, y: h - stemH - 7)
                            }

                            // Carb label
                            if bolus.carbs > 0 {
                                Text("\(bolus.carbs)g")
                                    .font(.system(size: 6).weight(.medium))
                                    .foregroundStyle(Theme.teal.opacity(0.5))
                                    .position(x: x, y: h - stemH - (bolus.units >= 3 ? 15 : 7))
                            }
                        }
                    }
                }

                // --- Glucose line segments colored by range ---
                // Draw segments between consecutive points, colored by status
                ForEach(0..<max(0, glucosePoints.count - 1), id: \.self) { i in
                    let pt1 = glucosePoints[i]
                    let pt2 = glucosePoints[i + 1]
                    let gap = pt2.timestamp.timeIntervalSince(pt1.timestamp)

                    if gap <= 900 {
                        let x1 = chartL + chartW * CGFloat(pt1.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange)
                        let y1 = h - (CGFloat(pt1.value - minVal) / gRange) * h
                        let x2 = chartL + chartW * CGFloat(pt2.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange)
                        let y2 = h - (CGFloat(pt2.value - minVal) / gRange) * h

                        // Color based on the average of the two points
                        let avgVal = (pt1.value + pt2.value) / 2
                        let segColor: Color = avgVal < 70 ? Theme.low :
                            avgVal <= 180 ? Theme.primary :
                            avgVal <= 250 ? Theme.elevated : Theme.high

                        Path { p in
                            p.move(to: CGPoint(x: x1, y: y1))
                            p.addLine(to: CGPoint(x: x2, y: y2))
                        }
                        .stroke(segColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }

                // --- Scrubber ---
                if let idx = selectedGlucoseIndex, idx < glucosePoints.count {
                    let pt = glucosePoints[idx]
                    let sx = chartL + chartW * CGFloat(pt.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange)
                    let sy = h - (CGFloat(pt.value - minVal) / gRange) * h

                    // Vertical line
                    Path { p in
                        p.move(to: CGPoint(x: sx, y: 0))
                        p.addLine(to: CGPoint(x: sx, y: h))
                    }
                    .stroke(Theme.textTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Find nearest bolus to scrubber
                    let nearestBolus = bolusPoints.min(by: {
                        abs($0.timestamp.timeIntervalSince1970 - pt.timestamp.timeIntervalSince1970) <
                        abs($1.timestamp.timeIntervalSince1970 - pt.timestamp.timeIntervalSince1970)
                    })
                    let bolusNearby = nearestBolus.flatMap { bolus -> BolusPoint? in
                        abs(bolus.timestamp.timeIntervalSince(pt.timestamp)) < timeRange * 0.03 ? bolus : nil
                    }

                    // Tooltip
                    VStack(spacing: 2) {
                        Text("\(pt.value)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.statusColor(pt.status))
                        if let b = bolusNearby {
                            Text(String(format: "%.1fu", b.units))
                                .font(.system(size: 8).weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.teal)
                        }
                        Text(pt.timestamp, format: .dateTime.hour().minute())
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.border, lineWidth: 0.5))
                    .position(x: min(max(sx, 44), w - 44), y: max(sy - 28, 16))
                }

                // --- Latest point ---
                if selectedGlucoseIndex == nil, let last = glucosePoints.last {
                    let lx = chartL + chartW * CGFloat(last.timestamp.timeIntervalSince1970 - minTime) / CGFloat(timeRange)
                    let ly = h - (CGFloat(last.value - minVal) / gRange) * h
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.statusColor(last.status))
                        .frame(width: 6, height: 6)
                        .position(x: lx, y: ly)
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
                        var nearest = 0
                        var nearestDist = Double.infinity
                        for (i, pt) in glucosePoints.enumerated() {
                            let dist = abs(pt.timestamp.timeIntervalSince1970 - targetTime)
                            if dist < nearestDist { nearestDist = dist; nearest = i }
                        }
                        selectedGlucoseIndex = nearest
                    }
                    .onEnded { _ in
                        isDragging = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.2)) { selectedGlucoseIndex = nil }
                        }
                    }
            )
        }
    }

    // Smart y-axis steps for insulin
    private var insulinYSteps: [Double] {
        if maxBolus <= 4 { return [0, 2, 4] }
        if maxBolus <= 6 { return [0, 3, 6] }
        if maxBolus <= 10 { return [0, 5, 10] }
        return [0, 5, 10, Double(Int(maxBolus))]
    }

    // MARK: - Time Axis

    private var timeAxis: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let chartW = w - chartL - chartR
            let labelCount = 5

            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: chartL, y: 0))
                    p.addLine(to: CGPoint(x: chartL + chartW, y: 0))
                }
                .stroke(Theme.border, lineWidth: 0.5)

                ForEach(0..<labelCount, id: \.self) { i in
                    let t = minTime + timeRange * Double(i) / Double(labelCount - 1)
                    let x = chartL + chartW * CGFloat(i) / CGFloat(labelCount - 1)
                    Text(Date(timeIntervalSince1970: t), format: .dateTime.hour().minute())
                        .font(.system(size: 7).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                        .position(x: x, y: 8)
                }
            }
        }
    }
}

#Preview {
    StackedChartView(glucosePoints: [], bolusPoints: [])
        .frame(height: 240)
        .padding()
}
