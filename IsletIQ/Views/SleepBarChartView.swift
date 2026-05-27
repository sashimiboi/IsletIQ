import SwiftUI
import Charts

/// Bar chart of nightly sleep over the last 1d / 2d / 14d / 30d.
/// Each bar is one night, stacked by sleep stage (deep / REM / core / awake).
/// Date axis labels run through `ChartAxisFormat` so they read as
/// "Apr 14" on multi-day ranges instead of "12 AM".
struct SleepBarChartView: View {
    let nights: [SleepData]
    let range: ChartRange

    @State private var selectedDay: Date?

    private struct Bar: Identifiable {
        let id = UUID()
        let date: Date
        let stage: SleepStage
        let hours: Double
    }

    private let stageColors: [SleepStage: Color] = [
        .awake: Color(red: 0.9, green: 0.35, blue: 0.3),
        .rem: Color(red: 0.55, green: 0.75, blue: 0.95),
        .core: Color(red: 0.25, green: 0.45, blue: 0.9),
        .deep: Color(red: 0.4, green: 0.3, blue: 0.8),
    ]

    private var bars: [Bar] {
        var out: [Bar] = []
        for night in nights {
            // Anchor each night to its wake-time calendar day so the
            // bar lines up with the day the user actually woke up on.
            let day = Calendar.current.startOfDay(for: night.wakeTime)
            out.append(Bar(date: day, stage: .deep, hours: night.deepMinutes / 60))
            out.append(Bar(date: day, stage: .rem,  hours: night.remMinutes / 60))
            out.append(Bar(date: day, stage: .core, hours: night.coreMinutes / 60))
            out.append(Bar(date: day, stage: .awake, hours: night.awakeMinutes / 60))
        }
        return out
    }

    var body: some View {
        if nights.isEmpty {
            Text("No sleep recorded in this range")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            Chart(bars) { bar in
                BarMark(
                    x: .value("Date", bar.date, unit: .day),
                    y: .value("Hours", bar.hours)
                )
                .foregroundStyle(stageColors[bar.stage] ?? .gray)
                .cornerRadius(3)
                .opacity(opacity(for: bar.date))

                if let selected = selectedDay,
                   Calendar.current.isDate(bar.date, inSameDayAs: selected),
                   bar.stage == .deep {
                    RuleMark(x: .value("Selected", bar.date, unit: .day))
                        .foregroundStyle(Theme.textTertiary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXSelection(value: $selectedDay)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: strideCount)) { value in
                    AxisGridLine()
                    AxisTick()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(ChartAxisFormat.label(for: date, range: range))
                                .font(.system(size: 9).monospacedDigit())
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text("\(Int(h))h").font(.system(size: 9).monospacedDigit())
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let selected = selectedDay,
                       let night = nightFor(selected),
                       let xPos = proxy.position(forX: Calendar.current.startOfDay(for: night.wakeTime)) {
                        let plotFrame = geo[proxy.plotFrame!]
                        let tooltipX = min(max(xPos + plotFrame.minX, 80), geo.size.width - 80)
                        SleepTooltip(night: night)
                            .position(x: tooltipX, y: 32)
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 12) {
                HStack(spacing: 12) {
                    legendDot(.deep, "Deep")
                    legendDot(.rem, "REM")
                    legendDot(.core, "Core")
                    legendDot(.awake, "Awake")
                }
            }
            .frame(height: 240)
        }
    }

    private func nightFor(_ day: Date) -> SleepData? {
        let cal = Calendar.current
        return nights.first { cal.isDate(cal.startOfDay(for: $0.wakeTime), inSameDayAs: day) }
    }

    /// Dim non-selected bars so the focused night reads first.
    private func opacity(for date: Date) -> Double {
        guard let selected = selectedDay else { return 1.0 }
        return Calendar.current.isDate(date, inSameDayAs: selected) ? 1.0 : 0.35
    }

    /// How many days each AxisMark step covers.
    /// 1d/2d ranges are ignored (they show a single bar each), so the
    /// stride is anchored to multi-day ranges.
    private var strideCount: Int {
        switch range {
        case .day, .threeDays: 1
        case .fourteenDays: 2
        case .thirtyDays: 5
        }
    }

    @ViewBuilder
    private func legendDot(_ stage: SleepStage, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(stageColors[stage] ?? .gray)
                .frame(width: 10, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct SleepTooltip: View {
    let night: SleepData

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.dateFormatter.string(from: night.wakeTime))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(String(format: "%.1f hrs total", night.totalHours))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.primary)
            HStack(spacing: 6) {
                stagePill("Deep", minutes: night.deepMinutes, color: Color(red: 0.4, green: 0.3, blue: 0.8))
                stagePill("REM",  minutes: night.remMinutes,  color: Color(red: 0.55, green: 0.75, blue: 0.95))
                stagePill("Core", minutes: night.coreMinutes, color: Color(red: 0.25, green: 0.45, blue: 0.9))
            }
            HStack(spacing: 4) {
                Text(Self.timeFormatter.string(from: night.bedtime))
                Text("→")
                Text(Self.timeFormatter.string(from: night.wakeTime))
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    @ViewBuilder
    private func stagePill(_ label: String, minutes: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(minutes))m")
                .font(.system(size: 9).weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
