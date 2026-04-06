import SwiftUI

/// Sleep stages timeline chart - Apple Sleep app style with STD principles
struct SleepChartView: View {
    let sleep: SleepData
    @State private var selectedSegment: SleepSegment?

    private let stageColors: [SleepStage: Color] = [
        .awake: Color.orange.opacity(0.7),
        .rem: Color(red: 0.4, green: 0.6, blue: 0.9),
        .core: Color(red: 0.25, green: 0.4, blue: 0.75),
        .deep: Color(red: 0.15, green: 0.2, blue: 0.55),
    ]

    private let stageLabels: [SleepStage] = [.awake, .rem, .core, .deep]
    private let labelW: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let chartW = w - labelW
                let bedtime = sleep.bedtime.timeIntervalSince1970
                let wakeTime = sleep.wakeTime.timeIntervalSince1970
                let timeRange = max(1, wakeTime - bedtime)
                let rowH = h / 4.0

                ZStack(alignment: .topLeading) {
                    // Y-axis stage labels
                    ForEach(Array(stageLabels.enumerated()), id: \.offset) { i, stage in
                        Text(stage.rawValue)
                            .font(.system(size: 8).weight(.medium))
                            .foregroundStyle(stageColors[stage] ?? .gray)
                            .frame(width: labelW, alignment: .trailing)
                            .position(x: labelW / 2, y: rowH * CGFloat(i) + rowH / 2)
                    }

                    // Horizontal gridlines
                    ForEach(0..<4, id: \.self) { i in
                        let y = rowH * CGFloat(i)
                        Path { p in
                            p.move(to: CGPoint(x: labelW, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                    }

                    // Sleep stage blocks
                    ForEach(sleep.segments) { segment in
                        let x1 = labelW + chartW * CGFloat((segment.start.timeIntervalSince1970 - bedtime) / timeRange)
                        let x2 = labelW + chartW * CGFloat((segment.end.timeIntervalSince1970 - bedtime) / timeRange)
                        let segW = max(1, x2 - x1)
                        let row = CGFloat(segment.stage.depth)
                        let y = row * rowH
                        let isSelected = selectedSegment?.id == segment.id

                        RoundedRectangle(cornerRadius: 2)
                            .fill(stageColors[segment.stage] ?? .gray)
                            .opacity(isSelected ? 1.0 : (selectedSegment == nil ? 1.0 : 0.4))
                            .frame(width: segW, height: rowH - 2)
                            .position(x: x1 + segW / 2, y: y + rowH / 2)
                    }

                    // Step line connecting stages
                    if sleep.segments.count > 1 {
                        Path { path in
                            for (i, segment) in sleep.segments.enumerated() {
                                let x = labelW + chartW * CGFloat((segment.start.timeIntervalSince1970 - bedtime) / timeRange)
                                let xEnd = labelW + chartW * CGFloat((segment.end.timeIntervalSince1970 - bedtime) / timeRange)
                                let y = rowH * CGFloat(segment.stage.depth) + rowH / 2

                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                                path.addLine(to: CGPoint(x: xEnd, y: y))
                            }
                        }
                        .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }

                    // Tooltip
                    if let seg = selectedSegment {
                        let xMid = labelW + chartW * CGFloat(((seg.start.timeIntervalSince1970 + seg.end.timeIntervalSince1970) / 2 - bedtime) / timeRange)

                        Path { p in
                            p.move(to: CGPoint(x: xMid, y: 0))
                            p.addLine(to: CGPoint(x: xMid, y: h))
                        }
                        .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        let dotY = rowH * CGFloat(seg.stage.depth) + rowH / 2
                        Circle()
                            .fill(stageColors[seg.stage] ?? .gray)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .position(x: xMid, y: dotY)

                        let tooltipX = min(max(xMid, 70), w - 70)
                        let tooltipY: CGFloat = dotY > h / 2 ? dotY - 36 : dotY + 36

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(stageColors[seg.stage] ?? .gray)
                                    .frame(width: 8, height: 8)
                                Text(seg.stage.rawValue)
                                    .font(.system(size: 10).weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            Text("\(Int(seg.durationMinutes)) min")
                                .font(.system(size: 9).weight(.bold).monospacedDigit())
                                .foregroundStyle(stageColors[seg.stage] ?? .gray)
                            HStack(spacing: 2) {
                                Text(seg.start, format: .dateTime.hour().minute())
                                Text("-")
                                Text(seg.end, format: .dateTime.hour().minute())
                            }
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                        .position(x: tooltipX, y: tooltipY)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let xPct = max(0, min(1, (drag.location.x - labelW) / chartW))
                            let touchTime = bedtime + xPct * timeRange

                            let match = sleep.segments.first { seg in
                                touchTime >= seg.start.timeIntervalSince1970 &&
                                touchTime <= seg.end.timeIntervalSince1970
                            }

                            if let match {
                                selectedSegment = match
                            } else {
                                selectedSegment = sleep.segments.min(by: {
                                    let mid0 = ($0.start.timeIntervalSince1970 + $0.end.timeIntervalSince1970) / 2
                                    let mid1 = ($1.start.timeIntervalSince1970 + $1.end.timeIntervalSince1970) / 2
                                    return abs(mid0 - touchTime) < abs(mid1 - touchTime)
                                })
                            }
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedSegment = nil }
                            }
                        }
                )
            }
            .frame(height: 120)

            // Time axis
            HStack {
                Text(sleep.bedtime, format: .dateTime.hour().minute())
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                let midTime = Date(timeIntervalSince1970: (sleep.bedtime.timeIntervalSince1970 + sleep.wakeTime.timeIntervalSince1970) / 2)
                Text(midTime, format: .dateTime.hour().minute())
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(sleep.wakeTime, format: .dateTime.hour().minute())
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.leading, 40)

            // Legend
            HStack(spacing: 12) {
                ForEach(stageLabels, id: \.rawValue) { stage in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(stageColors[stage] ?? .gray)
                            .frame(width: 8, height: 4)
                        Text(stage.rawValue)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }
}
