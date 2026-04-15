import SwiftUI

struct SleepChartView: View {
    let sleep: SleepData
    @State private var selectedSegment: SleepSegment?

    private let stageColors: [SleepStage: Color] = [
        .awake: Color(red: 0.9, green: 0.35, blue: 0.3),
        .rem: Color(red: 0.55, green: 0.75, blue: 0.95),
        .core: Color(red: 0.25, green: 0.45, blue: 0.9),
        .deep: Color(red: 0.4, green: 0.3, blue: 0.8),
    ]

    private let stageLabels: [SleepStage] = [.awake, .rem, .core, .deep]
    private let labelW: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let chartW = w - labelW
                let bedtime = sleep.bedtime.timeIntervalSince1970
                let wakeTime = sleep.wakeTime.timeIntervalSince1970
                let timeRange = max(1, wakeTime - bedtime)
                let rowH = h / 4.0
                let blockH = rowH * 0.75

                Canvas { context, size in
                    // Gridlines
                    for i in 0...4 {
                        let y = rowH * CGFloat(i)
                        var path = Path()
                        path.move(to: CGPoint(x: labelW, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                        context.stroke(path, with: .color(.gray.opacity(0.08)), lineWidth: 0.5)
                    }

                    // Draw segments with connectors
                    for (_, segment) in sleep.segments.enumerated() {
                        let x1 = labelW + chartW * CGFloat((segment.start.timeIntervalSince1970 - bedtime) / timeRange)
                        let x2 = labelW + chartW * CGFloat((segment.end.timeIntervalSince1970 - bedtime) / timeRange)
                        let segW = max(2, x2 - x1)
                        let depth = CGFloat(segment.stage.depth)
                        let yCenter = depth * rowH + rowH / 2
                        let color = stageColors[segment.stage] ?? .blue
                        let isSelected = selectedSegment?.id == segment.id
                        let opacity: Double = isSelected ? 1.0 : (selectedSegment == nil ? 0.85 : 0.25)

                        // Block
                        let blockRect = CGRect(x: x1, y: yCenter - blockH / 2, width: segW, height: blockH)
                        let blockPath = RoundedRectangle(cornerRadius: 3).path(in: blockRect)
                        context.fill(blockPath, with: .color(color.opacity(opacity)))
                    }
                }

                // Y-axis labels (on top of canvas)
                ForEach(Array(stageLabels.enumerated()), id: \.offset) { i, stage in
                    Text(stage.rawValue)
                        .font(.system(size: 8).weight(.semibold))
                        .foregroundStyle(stageColors[stage]!)
                        .position(x: labelW / 2, y: rowH * CGFloat(i) + rowH / 2)
                }

                // Tooltip
                if let seg = selectedSegment {
                    let xMid = labelW + chartW * CGFloat(((seg.start.timeIntervalSince1970 + seg.end.timeIntervalSince1970) / 2 - bedtime) / timeRange)
                    let dotY = rowH * CGFloat(seg.stage.depth) + rowH / 2
                    let tooltipX = min(max(xMid, 65), w - 65)
                    let tooltipY: CGFloat = dotY > h / 2 ? dotY - 34 : dotY + 34

                    // Scrubber
                    Path { p in
                        p.move(to: CGPoint(x: xMid, y: 0))
                        p.addLine(to: CGPoint(x: xMid, y: h))
                    }
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)

                    Circle()
                        .fill(stageColors[seg.stage]!)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .position(x: xMid, y: dotY)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(stageColors[seg.stage]!).frame(width: 8, height: 8)
                            Text(seg.stage.rawValue).font(.system(size: 10).weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        }
                        Text("\(Int(seg.durationMinutes)) min")
                            .font(.system(size: 9).weight(.bold).monospacedDigit())
                            .foregroundStyle(stageColors[seg.stage]!)
                        HStack(spacing: 2) {
                            Text(seg.start, format: .dateTime.hour().minute())
                            Text("-")
                            Text(seg.end, format: .dateTime.hour().minute())
                        }
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    .position(x: tooltipX, y: tooltipY)
                }

                // Gesture overlay
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let xPct = max(0, min(1, (drag.location.x - labelW) / chartW))
                                let touchTime = bedtime + xPct * timeRange
                                selectedSegment = sleep.segments.first {
                                    touchTime >= $0.start.timeIntervalSince1970 && touchTime <= $0.end.timeIntervalSince1970
                                } ?? sleep.segments.min(by: {
                                    abs(($0.start.timeIntervalSince1970 + $0.end.timeIntervalSince1970) / 2 - touchTime) <
                                    abs(($1.start.timeIntervalSince1970 + $1.end.timeIntervalSince1970) / 2 - touchTime)
                                })
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation(.easeOut(duration: 0.2)) { selectedSegment = nil }
                                }
                            }
                    )
            }
            .frame(height: 130)

            // Time axis
            HStack {
                let bedStr = sleep.bedtime
                let wakeStr = sleep.wakeTime
                let q1 = Date(timeIntervalSince1970: sleep.bedtime.timeIntervalSince1970 + (sleep.wakeTime.timeIntervalSince1970 - sleep.bedtime.timeIntervalSince1970) * 0.33)
                let q2 = Date(timeIntervalSince1970: sleep.bedtime.timeIntervalSince1970 + (sleep.wakeTime.timeIntervalSince1970 - sleep.bedtime.timeIntervalSince1970) * 0.66)
                Text(bedStr, format: .dateTime.hour().minute())
                Spacer()
                Text(q1, format: .dateTime.hour().minute())
                Spacer()
                Text(q2, format: .dateTime.hour().minute())
                Spacer()
                Text(wakeStr, format: .dateTime.hour().minute())
            }
            .font(.system(size: 8).monospacedDigit())
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, labelW)

            // Legend
            HStack(spacing: 12) {
                ForEach(stageLabels, id: \.rawValue) { stage in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(stageColors[stage]!).frame(width: 8, height: 4)
                        Text(stage.rawValue).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }
}
