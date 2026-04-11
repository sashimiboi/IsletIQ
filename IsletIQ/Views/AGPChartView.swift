import SwiftUI

struct AGPBand {
    let hour: Double
    let min: Double
    let p10: Double
    let p25: Double
    let median: Double
    let p75: Double
    let p90: Double
    let max: Double
}

/// Ambulatory Glucose Profile - Glooko-style clinical design
struct AGPChartView: View {
    let readings: [ReadingPoint]
    var agpRange: ChartRange = .fourteenDays

    @State private var selectedSlot: Int? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var cachedBands: [AGPBand]?

    private var bands: [AGPBand] {
        if let cached = cachedBands { return cached }
        return computeBands()
    }

    private func computeBands() -> [AGPBand] {
        let cutoff = Date().addingTimeInterval(-agpRange.seconds)
        let filtered = readings.filter { $0.timestamp >= cutoff }

        var slots: [Int: [Int]] = [:]
        for r in filtered {
            let cal = Calendar.current
            let hour = cal.component(.hour, from: r.timestamp)
            let minute = cal.component(.minute, from: r.timestamp)
            let slot = hour * 2 + (minute >= 30 ? 1 : 0)
            slots[slot, default: []].append(r.value)
        }

        var result: [AGPBand] = []
        for slot in 0..<48 {
            guard let values = slots[slot], values.count >= 2 else { continue }
            let sorted = values.sorted()
            let count = sorted.count

            func pct(_ p: Double) -> Double {
                let idx = p * Double(count - 1)
                let lower = Int(floor(idx))
                let upper = Swift.min(lower + 1, count - 1)
                let frac = idx - Double(lower)
                return Double(sorted[lower]) * (1 - frac) + Double(sorted[upper]) * frac
            }

            result.append(AGPBand(
                hour: Double(slot) / 2.0,
                min: Double(sorted.first!),
                p10: pct(0.1),
                p25: pct(0.25),
                median: pct(0.5),
                p75: pct(0.75),
                p90: pct(0.9),
                max: Double(sorted.last!)
            ))
        }
        return result.sorted { $0.hour < $1.hour }
    }

    // Layout
    private let chartL: CGFloat = 30
    private let chartR: CGFloat = 4

    // Dynamic y-axis based on data with 10% padding
    private var yMin: CGFloat {
        guard !bands.isEmpty else { return 40 }
        let lowest = CGFloat(bands.map(\.min).min() ?? 40)
        let padded = lowest - (lowest * 0.1)
        return max(0, padded)
    }
    private var yMax: CGFloat {
        guard !bands.isEmpty else { return 300 }
        let highest = CGFloat(bands.map(\.max).max() ?? 300)
        return highest * 1.1
    }

    // Dynamic y-axis labels: always include 70 and 180, plus evenly spaced steps
    private var yAxisLabels: [Int] {
        var labels: Set<Int> = [70, 180]
        let step = yMax - yMin > 200 ? 50 : 40
        var v = Int(ceil(yMin / CGFloat(step))) * step
        while v <= Int(yMax) {
            labels.insert(v)
            v += step
        }
        return labels.sorted()
    }

    private let bandBlue = Color(red: 0.35, green: 0.5, blue: 0.85)
    private let medianBlue = Color(red: 0.1, green: 0.15, blue: 0.45)

    var body: some View {
        GeometryReader { outerGeo in
            let baseW = outerGeo.size.width
            let chartH = outerGeo.size.height - 18 // reserve space for x-axis

            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    agpContent(baseWidth: baseW, h: chartH)
                        .frame(width: baseW * zoomScale, height: chartH)
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

                // X-axis time labels (always visible)
                GeometryReader { xGeo in
                    let xW = xGeo.size.width
                    let xChartW = xW - chartL - chartR
                    ForEach([0, 3, 6, 9, 12, 15, 18, 21], id: \.self) { hr in
                        Text(hourLabel(hr))
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .position(x: chartL + xChartW * CGFloat(hr) / 24.0, y: 9)
                    }
                }
                .frame(height: 18)
            }
        }
        .onAppear { cachedBands = computeBands() }
    }

    private func agpContent(baseWidth: CGFloat, h: CGFloat) -> some View {
        let w = baseWidth * zoomScale
        let chartW = w - chartL - chartR
        let yRange = yMax - yMin

        return ZStack(alignment: .topLeading) {
            // Y-axis labels (outside clip)
            ForEach(yAxisLabels, id: \.self) { val in
                let y = yPos(val, h: h, range: yRange)
                if y > 6 && y < h - 6 {
                    Text("\(val)")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(val == 70 || val == 180 ? Color.green.opacity(0.7) : Theme.textTertiary)
                        .position(x: 14, y: y)
                }
            }

            // Chart area (clipped)
            ZStack(alignment: .topLeading) {
                // White chart background
                Rectangle()
                    .fill(Color.white)
                    .frame(width: chartW, height: h)
                    .offset(x: chartL)

                // Gridlines
                ForEach(yAxisLabels, id: \.self) { val in
                    let y = yPos(val, h: h, range: yRange)
                    if y > 0 && y < h {
                        Path { p in
                            p.move(to: CGPoint(x: chartL, y: y))
                            p.addLine(to: CGPoint(x: chartL + chartW, y: y))
                        }
                        .stroke(Color.gray.opacity(0.12), lineWidth: 0.5)
                    }
                }

                // Vertical time gridlines
                ForEach([0, 6, 12, 18], id: \.self) { hr in
                    let x = xPos(Double(hr), chartW: chartW)
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                    .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                }

                // Green target lines (70, 180) - always visible
                ForEach([70, 180], id: \.self) { val in
                    let y = h - (CGFloat(val) - yMin) / yRange * h
                    Path { p in
                        p.move(to: CGPoint(x: chartL, y: y))
                        p.addLine(to: CGPoint(x: chartL + chartW, y: y))
                    }
                    .stroke(Color.green.opacity(0.5), lineWidth: 1)
                }

                if bands.count >= 4 {
                    // 10-90% band
                    bandFillPath(h: h, chartW: chartW, yRange: yRange, upper: \.p90, lower: \.p10)
                        .fill(bandBlue.opacity(0.15))

                    // 25-75% band
                    bandFillPath(h: h, chartW: chartW, yRange: yRange, upper: \.p75, lower: \.p25)
                        .fill(bandBlue.opacity(0.3))

                    // Min/Max dashed lines
                    linePath(h: h, chartW: chartW, yRange: yRange, value: \.min)
                        .stroke(bandBlue.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    linePath(h: h, chartW: chartW, yRange: yRange, value: \.max)
                        .stroke(bandBlue.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    // Median line
                    linePath(h: h, chartW: chartW, yRange: yRange, value: \.median)
                        .stroke(medianBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    // --- Tooltip scrubber ---
                    if let slot = selectedSlot, let band = bands.first(where: { Int($0.hour * 2) == slot }) {
                        let x = xPos(band.hour, chartW: chartW)
                        let medY = yPos(Int(band.median), h: h, range: yRange)

                        // Vertical scrubber line
                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                        }
                        .stroke(medianBlue.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        // Dot on median
                        Circle()
                            .fill(medianBlue)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .position(x: x, y: medY)

                        // Tooltip card
                        let tooltipX = min(max(x, 80), w - 80)
                        let tooltipY = max(medY - 60, 50)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(slotTimeLabel(slot))
                                .font(.system(size: 9).weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)

                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    tooltipRow(label: "25-75%", value: "\(Int(band.p25))-\(Int(band.p75))")
                                    tooltipRow(label: "10-90%", value: "\(Int(band.p10))-\(Int(band.p90))")
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    tooltipRow(label: "Median", value: "\(Int(band.median))")
                                    tooltipRow(label: "Range", value: "\(Int(band.min))-\(Int(band.max))")
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        .position(x: tooltipX, y: tooltipY)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title3)
                            .foregroundStyle(Theme.textTertiary)
                        Text("Need 3+ days of data for AGP")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .position(x: w / 2, y: h / 2)
                }

            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let xPct = max(0, min(1, (drag.location.x - chartL) / chartW))
                    let hour = xPct * 24.0
                    let nearestSlot = Int(round(hour * 2))
                    if let _ = bands.first(where: { Int($0.hour * 2) == nearestSlot }) {
                        selectedSlot = nearestSlot
                    } else {
                        let closest = bands.min(by: { abs(Int($0.hour * 2) - nearestSlot) < abs(Int($1.hour * 2) - nearestSlot) })
                        selectedSlot = closest.map { Int($0.hour * 2) }
                    }
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.2)) { selectedSlot = nil }
                    }
                }
        )
        } // end ZStack
    } // end agpContent

    // MARK: - Positioning helpers

    private func xPos(_ hour: Double, chartW: CGFloat) -> CGFloat {
        chartL + chartW * CGFloat(hour / 24.0)
    }

    private func yPos(_ val: Int, h: CGFloat, range: CGFloat) -> CGFloat {
        h - (CGFloat(val) - yMin) / range * h
    }

    // MARK: - Path builders

    private func linePath(h: CGFloat, chartW: CGFloat, yRange: CGFloat, value: KeyPath<AGPBand, Double>) -> Path {
        let points = bands.map { b -> CGPoint in
            CGPoint(x: xPos(b.hour, chartW: chartW),
                    y: h - (CGFloat(b[keyPath: value]) - yMin) / yRange * h)
        }
        return catmullRom(points)
    }

    private func bandFillPath(h: CGFloat, chartW: CGFloat, yRange: CGFloat, upper: KeyPath<AGPBand, Double>, lower: KeyPath<AGPBand, Double>) -> Path {
        let upperPts = bands.map { b -> CGPoint in
            CGPoint(x: xPos(b.hour, chartW: chartW),
                    y: h - (CGFloat(b[keyPath: upper]) - yMin) / yRange * h)
        }
        let lowerPts = bands.reversed().map { b -> CGPoint in
            CGPoint(x: xPos(b.hour, chartW: chartW),
                    y: h - (CGFloat(b[keyPath: lower]) - yMin) / yRange * h)
        }

        guard !upperPts.isEmpty, !lowerPts.isEmpty else { return Path() }

        // Upper spline forward
        var path = catmullRom(upperPts)

        // Straight line to first lower point, then lower spline
        if let firstLower = lowerPts.first {
            path.addLine(to: firstLower)
        }
        // Add lower curve segments inline (no move-to)
        if lowerPts.count >= 2 {
            for i in 0..<(lowerPts.count - 1) {
                let p0 = i > 0 ? lowerPts[i - 1] : lowerPts[i]
                let p1 = lowerPts[i]
                let p2 = lowerPts[i + 1]
                let p3 = i + 2 < lowerPts.count ? lowerPts[i + 2] : p2

                let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)

                if i == 0 {
                    // Already at firstLower via addLine, just curve to next
                    path.addCurve(to: p2, control1: cp1, control2: cp2)
                } else {
                    path.addCurve(to: p2, control1: cp1, control2: cp2)
                }
            }
        }
        path.closeSubpath()
        return path
    }

    // Catmull-Rom spline
    private func catmullRom(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        if points.count == 2 {
            path.move(to: points[0])
            path.addLine(to: points[1])
            return path
        }

        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : p2

            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }

    // MARK: - Labels

    private func tooltipRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8).weight(.medium))
                .foregroundStyle(Theme.textTertiary)
            Text("\(value) mg/dL")
                .font(.system(size: 8).weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func slotTimeLabel(_ slot: Int) -> String {
        let startHour = slot / 2
        let startMin = (slot % 2) * 30
        let endSlot = slot + 1
        let endHour = endSlot / 2
        let endMin = (endSlot % 2) * 30
        return "Between \(fmtTime(startHour, startMin)) - \(fmtTime(endHour, endMin))"
    }

    private func fmtTime(_ hour: Int, _ min: Int) -> String {
        let h = hour % 24
        let period = h < 12 ? "AM" : "PM"
        let display = h == 0 ? 12 : h > 12 ? h - 12 : h
        return String(format: "%d:%02d %@", display, min, period)
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
}

#Preview {
    AGPChartView(readings: [])
        .frame(height: 220)
        .padding()
}
