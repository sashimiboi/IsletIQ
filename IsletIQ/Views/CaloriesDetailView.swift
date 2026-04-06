import SwiftUI

struct CaloriesDetailView: View {
    var healthKit: HealthKitManager?
    @State private var selectedTab: CalPeriod = .today
    @State private var selectedBar: Int? = nil
    @Environment(\.dismiss) private var dismiss

    enum CalPeriod: String, CaseIterable {
        case today = "Today"
        case threeDays = "3d"
        case week = "7d"
        case month = "30d"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("\(filteredCalTotal)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.elevated)
                        Text(selectedTab == .today ? "active cal today" : "active cal (\(selectedTab.rawValue))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 8)

                    HStack(spacing: 4) {
                        ForEach(CalPeriod.allCases, id: \.self) { period in
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
                                        selectedTab == period ? Theme.elevated : Theme.muted,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

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
            .navigationTitle("Active Calories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
            .task {
                await healthKit?.fetchHourlyCals()
                await healthKit?.fetchWeeklyCals()
            }
        }
    }

    // MARK: - Hourly Chart

    private var hourlyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calories by Hour")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let idx = selectedBar, let data = healthKit?.hourlyCals, idx < data.count {
                    Text("\(Int(data[idx].cals)) cal")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.elevated)
                }
            }

            let data = healthKit?.hourlyCals ?? []
            let maxCals = max(10, data.map(\.cals).max() ?? 10)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let barCount = max(1, data.count)
                let gap: CGFloat = 2
                let barW = (w - CGFloat(barCount - 1) * gap) / CGFloat(barCount)

                ZStack(alignment: .topLeading) {
                    ForEach(Array(data.enumerated()), id: \.offset) { i, entry in
                        let barH = max(2, h * CGFloat(entry.cals / maxCals))
                        let x = CGFloat(i) * (barW + gap)
                        let isSelected = selectedBar == i

                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? Theme.elevated : Theme.elevated.opacity(0.5))
                            .frame(width: barW, height: barH)
                            .position(x: x + barW / 2, y: h - barH / 2)
                    }

                    if let idx = selectedBar, idx < data.count {
                        let x = CGFloat(idx) * (barW + gap) + barW / 2
                        let entry = data[idx]
                        let barH = h * CGFloat(entry.cals / maxCals)

                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                        }
                        .stroke(Theme.elevated.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        VStack(spacing: 2) {
                            Text("\(Int(entry.cals))")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.elevated)
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
                            let idx = Int(drag.location.x / ((barW + gap)))
                            if idx >= 0 && idx < data.count { selectedBar = idx }
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedBar = nil }
                            }
                        }
                )
            }
            .frame(height: 160)

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

    // MARK: - Daily Chart

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calories by Day")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let idx = selectedBar, let data = filteredDailyCals, idx < data.count {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(data[idx].cals)) cal")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.elevated)
                        Text(data[idx].date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            let data = filteredDailyCals ?? []
            let maxCals = max(10, data.map(\.cals).max() ?? 10)
            let avgCals = data.isEmpty ? 0 : Int(data.map(\.cals).reduce(0, +) / Double(data.count))

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let barCount = max(1, data.count)
                let gap: CGFloat = barCount > 14 ? 1 : (barCount > 7 ? 3 : 6)
                let barW = max(4, (w - CGFloat(barCount - 1) * gap) / CGFloat(barCount))

                ZStack(alignment: .topLeading) {
                    if avgCals > 0 {
                        let avgY = h - h * CGFloat(avgCals) / CGFloat(maxCals)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: avgY))
                            p.addLine(to: CGPoint(x: w, y: avgY))
                        }
                        .stroke(Theme.teal.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        Text("avg \(avgCals)")
                            .font(.system(size: 7).monospacedDigit())
                            .foregroundStyle(Theme.teal)
                            .position(x: w - 22, y: avgY - 7)
                    }

                    ForEach(Array(data.enumerated()), id: \.offset) { i, entry in
                        let barH = max(2, h * CGFloat(entry.cals / maxCals))
                        let x = CGFloat(i) * (barW + gap)
                        let isToday = Calendar.current.isDateInToday(entry.date)
                        let isSelected = selectedBar == i

                        RoundedRectangle(cornerRadius: barW > 8 ? 4 : 2)
                            .fill(isSelected ? Theme.elevated : (isToday ? Theme.elevated : Theme.elevated.opacity(0.4)))
                            .frame(width: barW, height: barH)
                            .position(x: x + barW / 2, y: h - barH / 2)
                    }

                    if let idx = selectedBar, idx < data.count {
                        let x = CGFloat(idx) * (barW + gap) + barW / 2
                        let entry = data[idx]
                        let barH = h * CGFloat(entry.cals / maxCals)

                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                        }
                        .stroke(Theme.elevated.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        VStack(spacing: 2) {
                            Text("\(Int(entry.cals))")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.elevated)
                            Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.textSecondary)
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
                            let barTotal = max(1, (geo.size.width - CGFloat(max(0, data.count - 1)) * gap) / CGFloat(max(1, data.count)) + gap)
                            let idx = Int(drag.location.x / barTotal)
                            if idx >= 0 && idx < data.count { selectedBar = idx }
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedBar = nil }
                            }
                        }
                )
            }
            .frame(height: 160)

            if !data.isEmpty {
                HStack {
                    Text(data.first!.date, format: .dateTime.month(.abbreviated).day())
                    Spacer()
                    if data.count > 2 {
                        Text(data[data.count / 2].date, format: .dateTime.month(.abbreviated).day())
                    }
                    Spacer()
                    Text(data.last!.date, format: .dateTime.month(.abbreviated).day())
                }
                .font(.system(size: 8).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(20)
        .card()
    }

    private var filteredCalTotal: Int {
        if selectedTab == .today {
            return Int(healthKit?.activeCaloriesToday ?? 0)
        }
        return Int((filteredDailyCals ?? []).map(\.cals).reduce(0, +))
    }

    private var filteredDailyCals: [(date: Date, cals: Double)]? {
        guard let data = healthKit?.weeklyCals else { return nil }
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
        let allData = healthKit?.weeklyCals ?? []
        let cutoff7 = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let weekly = allData.filter { $0.date >= cutoff7 }
        let totalWeek = Int(weekly.map(\.cals).reduce(0, +))
        let avgWeek = weekly.isEmpty ? 0 : totalWeek / weekly.count
        let bestDay = weekly.max(by: { $0.cals < $1.cals })

        return VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 0) {
                CalStatItem(label: "Today", value: "\(Int(healthKit?.activeCaloriesToday ?? 0))", color: Theme.elevated)
                Spacer()
                CalStatItem(label: "7-Day Avg", value: "\(avgWeek)", color: Theme.teal)
                Spacer()
                CalStatItem(label: "Best Day", value: "\(Int(bestDay?.cals ?? 0))", color: Theme.normal)
                Spacer()
                CalStatItem(label: "This Week", value: "\(totalWeek)", color: Theme.elevated)
            }
        }
        .padding(20)
        .card()
    }

    private func hourLabel(_ hr: Int) -> String {
        if hr == 0 { return "12a" }
        if hr < 12 { return "\(hr)a" }
        if hr == 12 { return "12p" }
        return "\(hr - 12)p"
    }
}

private struct CalStatItem: View {
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
