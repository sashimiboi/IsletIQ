import SwiftUI

struct StepsDetailView: View {
    var healthKit: HealthKitManager?
    @State private var selectedTab: StepsPeriod = .today
    @State private var selectedBar: Int? = nil
    @Environment(\.dismiss) private var dismiss

    enum StepsPeriod: String, CaseIterable {
        case today = "Today"
        case threeDays = "3d"
        case week = "7d"
        case month = "30d"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Total steps header - changes with filter
                    VStack(spacing: 4) {
                        Text("\(filteredStepTotal)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.primary)
                        Text(selectedTab == .today ? "steps today" : "steps (\(selectedTab.rawValue))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 8)

                    // Period toggles
                    HStack(spacing: 4) {
                        ForEach(StepsPeriod.allCases, id: \.self) { period in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = period
                                    selectedBar = nil
                                }
                            } label: {
                                Text(period.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(selectedTab == period ? .white : Theme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedTab == period ? Theme.primary : Theme.muted,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Chart
                    if selectedTab == .today {
                        hourlyChart
                    } else {
                        dailyChart
                    }

                    statsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Theme.bg)
            .navigationTitle("Steps")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
            .task {
                await healthKit?.fetchHourlySteps()
                await healthKit?.fetchWeeklySteps()
            }
        }
    }

    // MARK: - Hourly Bar Chart with Drag Tooltip

    private var hourlyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Steps by Hour")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let idx = selectedBar, let data = healthKit?.hourlySteps, idx < data.count {
                    Text("\(data[idx].steps) steps")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.primary)
                }
            }

            let data = healthKit?.hourlySteps ?? []
            let maxSteps = max(100, data.map(\.steps).max() ?? 100)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let barCount = max(1, data.count)
                let gap: CGFloat = 2
                let barW = (w - CGFloat(barCount - 1) * gap) / CGFloat(barCount)

                ZStack(alignment: .topLeading) {
                    // Goal line
                    let goalPerHr = 417
                    if goalPerHr < maxSteps {
                        let goalY = h - h * CGFloat(goalPerHr) / CGFloat(maxSteps)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: goalY))
                            p.addLine(to: CGPoint(x: w, y: goalY))
                        }
                        .stroke(Theme.normal.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        Text("10K goal")
                            .font(.system(size: 7))
                            .foregroundStyle(Theme.normal.opacity(0.5))
                            .position(x: w - 22, y: goalY - 7)
                    }

                    // Bars
                    ForEach(Array(data.enumerated()), id: \.offset) { i, entry in
                        let barH = max(2, h * CGFloat(entry.steps) / CGFloat(maxSteps))
                        let x = CGFloat(i) * (barW + gap)
                        let isSelected = selectedBar == i

                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? Theme.primary : Theme.primary.opacity(0.5))
                            .frame(width: barW, height: barH)
                            .position(x: x + barW / 2, y: h - barH / 2)
                    }

                    // Tooltip
                    if let idx = selectedBar, idx < data.count {
                        let x = CGFloat(idx) * (barW + gap) + barW / 2
                        let entry = data[idx]
                        let barH = h * CGFloat(entry.steps) / CGFloat(maxSteps)

                        // Vertical line
                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                        }
                        .stroke(Theme.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        // Tooltip card
                        VStack(spacing: 2) {
                            Text("\(entry.steps)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.primary)
                            Text(hourLabel(entry.hour))
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                        .position(x: min(max(x, 30), w - 30), y: max(h - barH - 20, 16))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let barTotal = barW + gap
                            let idx = Int(drag.location.x / barTotal)
                            if idx >= 0 && idx < data.count {
                                selectedBar = idx
                            }
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedBar = nil }
                            }
                        }
                )
            }
            .frame(height: 160)

            // Hour labels
            HStack {
                ForEach([0, 6, 12, 18, 23], id: \.self) { hr in
                    if hr > 0 { Spacer() }
                    Text(hourLabel(hr))
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Daily Bar Chart with Drag Tooltip

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Steps by Day")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let idx = selectedBar, let data = filteredWeeklySteps, idx < data.count {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(data[idx].steps)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.primary)
                        Text(data[idx].date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            let data = filteredWeeklySteps ?? []
            let maxSteps = max(100, data.map(\.steps).max() ?? 100)
            let avgSteps = data.isEmpty ? 0 : data.map(\.steps).reduce(0, +) / data.count

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let barCount = max(1, data.count)
                let gap: CGFloat = barCount > 14 ? 1 : (barCount > 7 ? 3 : 6)
                let barW = max(4, (w - CGFloat(barCount - 1) * gap) / CGFloat(barCount))

                ZStack(alignment: .topLeading) {
                    // Average line
                    if avgSteps > 0 {
                        let avgY = h - h * CGFloat(avgSteps) / CGFloat(maxSteps)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: avgY))
                            p.addLine(to: CGPoint(x: w, y: avgY))
                        }
                        .stroke(Theme.teal.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        Text("avg \(avgSteps)")
                            .font(.system(size: 7).monospacedDigit())
                            .foregroundStyle(Theme.teal)
                            .position(x: w - 22, y: avgY - 7)
                    }

                    // Bars
                    ForEach(Array(data.enumerated()), id: \.offset) { i, entry in
                        let barH = max(2, h * CGFloat(entry.steps) / CGFloat(maxSteps))
                        let x = CGFloat(i) * (barW + gap)
                        let isToday = Calendar.current.isDateInToday(entry.date)
                        let isSelected = selectedBar == i

                        RoundedRectangle(cornerRadius: barW > 8 ? 4 : 2)
                            .fill(isSelected ? Theme.primary : (isToday ? Theme.primary : Theme.primary.opacity(0.4)))
                            .frame(width: barW, height: barH)
                            .position(x: x + barW / 2, y: h - barH / 2)
                    }

                    // Tooltip
                    if let idx = selectedBar, idx < data.count {
                        let barTotal = barW + gap
                        let x = CGFloat(idx) * barTotal + barW / 2
                        let entry = data[idx]
                        let barH = h * CGFloat(entry.steps) / CGFloat(maxSteps)

                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                        }
                        .stroke(Theme.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        VStack(spacing: 2) {
                            Text("\(entry.steps)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.primary)
                            Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.textSecondary)
                            let miles = Double(entry.steps) * 0.0004
                            Text(String(format: "%.1f mi", miles))
                                .font(.system(size: 7).monospacedDigit())
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                        .position(x: min(max(x, 40), w - 40), y: max(h - barH - 24, 20))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let barTotal = barW + gap
                            let idx = Int(drag.location.x / barTotal)
                            if idx >= 0 && idx < data.count {
                                selectedBar = idx
                            }
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedBar = nil }
                            }
                        }
                )
            }
            .frame(height: 160)

            // Date labels
            if !data.isEmpty {
                HStack {
                    Text(data.first!.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    if data.count > 2 {
                        let mid = data[data.count / 2]
                        Text(mid.date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text(data.last!.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(20)
        .card()
    }

    private var filteredStepTotal: Int {
        if selectedTab == .today {
            return healthKit?.stepsToday ?? 0
        }
        return (filteredWeeklySteps ?? []).map(\.steps).reduce(0, +)
    }

    private var filteredWeeklySteps: [(date: Date, steps: Int)]? {
        guard let data = healthKit?.weeklySteps else { return nil }
        let days: Int
        switch selectedTab {
        case .today: days = 1
        case .threeDays: days = 3
        case .week: days = 7
        case .month: days = 30
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        return data.filter { $0.date >= cutoff }
    }

    // MARK: - Stats

    private var statsCard: some View {
        let allData = healthKit?.weeklySteps ?? []
        let cutoff7 = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let last7 = allData.filter { $0.date >= cutoff7 }
        let totalWeek = last7.map(\.steps).reduce(0, +)
        let avgWeek = last7.isEmpty ? 0 : totalWeek / last7.count
        let bestDay = last7.max(by: { $0.steps < $1.steps })

        return VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 0) {
                StatItem(label: "Today", value: "\(healthKit?.stepsToday ?? 0)", color: Theme.primary)
                Spacer()
                StatItem(label: "7-Day Avg", value: "\(avgWeek)", color: Theme.teal)
                Spacer()
                StatItem(label: "Best Day", value: "\(bestDay?.steps ?? 0)", color: Theme.normal)
                Spacer()
                StatItem(label: "This Week", value: "\(totalWeek)", color: Theme.primary)
            }

            let miles = Double(healthKit?.stepsToday ?? 0) * 0.0004
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(Theme.normal)
                Text(String(format: "%.1f miles today", miles))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Helpers

    private func hourLabel(_ hr: Int) -> String {
        if hr == 0 { return "12a" }
        if hr < 12 { return "\(hr)a" }
        if hr == 12 { return "12p" }
        return "\(hr - 12)p"
    }
}

private struct StatItem: View {
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
