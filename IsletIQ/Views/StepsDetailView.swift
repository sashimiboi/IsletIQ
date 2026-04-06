import SwiftUI

struct StepsDetailView: View {
    var healthKit: HealthKitManager?
    @State private var selectedTab: StepsPeriod = .today
    @State private var selectedBar: Int? = nil
    @Environment(\.dismiss) private var dismiss

    enum StepsPeriod: String, CaseIterable {
        case today = "Today"
        case week = "7 Days"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Total steps header
                    VStack(spacing: 4) {
                        Text("\(healthKit?.stepsToday ?? 0)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.primary)
                        Text("steps today")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 8)

                    // Period toggle
                    HStack(spacing: 0) {
                        ForEach(StepsPeriod.allCases, id: \.self) { period in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = period }
                            } label: {
                                Text(period.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selectedTab == period ? .white : Theme.textSecondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .background(
                                        selectedTab == period ? Theme.primary : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.muted, in: RoundedRectangle(cornerRadius: 9))

                    // Chart
                    if selectedTab == .today {
                        hourlyChart
                    } else {
                        weeklyChart
                    }

                    // Stats card
                    statsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Theme.bg)
            .navigationTitle("Steps")
            .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Hourly Bar Chart

    private var hourlyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps by Hour")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            let data = healthKit?.hourlySteps ?? []
            let maxSteps = max(1, data.map(\.steps).max() ?? 1)

            GeometryReader { geo in
                let barCount = max(1, data.count)
                let barW = max(4, (geo.size.width - CGFloat(barCount) * 2) / CGFloat(barCount))
                let h = geo.size.height

                ZStack(alignment: .bottom) {
                    // Goal line (10,000 steps distributed = ~417/hr)
                    let goalY = h * CGFloat(417) / CGFloat(maxSteps)
                    if goalY < h {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: h - goalY))
                            p.addLine(to: CGPoint(x: geo.size.width, y: h - goalY))
                        }
                        .stroke(Theme.normal.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(data.enumerated()), id: \.offset) { i, entry in
                            let barH = max(2, h * CGFloat(entry.steps) / CGFloat(maxSteps))
                            let isSelected = selectedBar == i

                            VStack(spacing: 2) {
                                if isSelected {
                                    Text("\(entry.steps)")
                                        .font(.system(size: 8).weight(.bold).monospacedDigit())
                                        .foregroundStyle(Theme.primary)
                                }

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isSelected ? Theme.primary : Theme.primary.opacity(0.6))
                                    .frame(width: barW, height: barH)
                            }
                            .onTapGesture { selectedBar = selectedBar == i ? nil : i }
                        }
                    }
                }
            }
            .frame(height: 140)

            // Hour labels
            HStack {
                ForEach([0, 6, 12, 18, 23], id: \.self) { hr in
                    if hr > 0 { Spacer() }
                    Text(hr == 0 ? "12a" : hr < 12 ? "\(hr)a" : hr == 12 ? "12p" : "\(hr-12)p")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Weekly Bar Chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps by Day")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            let data = healthKit?.weeklySteps ?? []
            let maxSteps = max(1, data.map(\.steps).max() ?? 1)
            let avgSteps = data.isEmpty ? 0 : data.map(\.steps).reduce(0, +) / data.count

            GeometryReader { geo in
                let barCount = max(1, data.count)
                let barW = max(20, (geo.size.width - CGFloat(barCount) * 8) / CGFloat(barCount))
                let h = geo.size.height

                ZStack(alignment: .bottom) {
                    // Average line
                    if avgSteps > 0 {
                        let avgY = h * CGFloat(avgSteps) / CGFloat(maxSteps)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: h - avgY))
                            p.addLine(to: CGPoint(x: geo.size.width, y: h - avgY))
                        }
                        .stroke(Theme.teal.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        Text("avg \(avgSteps)")
                            .font(.system(size: 7).monospacedDigit())
                            .foregroundStyle(Theme.teal)
                            .position(x: geo.size.width - 24, y: h - avgY - 8)
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(data.enumerated()), id: \.offset) { i, entry in
                            let barH = max(2, h * CGFloat(entry.steps) / CGFloat(maxSteps))
                            let isToday = Calendar.current.isDateInToday(entry.date)
                            let isSelected = selectedBar == i + 100

                            VStack(spacing: 4) {
                                if isSelected {
                                    Text("\(entry.steps)")
                                        .font(.system(size: 9).weight(.bold).monospacedDigit())
                                        .foregroundStyle(Theme.primary)
                                }

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isToday ? Theme.primary : (isSelected ? Theme.primary.opacity(0.8) : Theme.primary.opacity(0.4)))
                                    .frame(width: barW, height: barH)

                                Text(entry.date, format: .dateTime.weekday(.narrow))
                                    .font(.system(size: 9).weight(isToday ? .bold : .regular))
                                    .foregroundStyle(isToday ? Theme.primary : Theme.textTertiary)
                            }
                            .onTapGesture { selectedBar = selectedBar == i + 100 ? nil : i + 100 }
                        }
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(20)
        .card()
    }

    // MARK: - Stats

    private var statsCard: some View {
        let weekly = healthKit?.weeklySteps ?? []
        let totalWeek = weekly.map(\.steps).reduce(0, +)
        let avgWeek = weekly.isEmpty ? 0 : totalWeek / weekly.count
        let bestDay = weekly.max(by: { $0.steps < $1.steps })

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

            // Distance estimate (~0.4 miles per 1000 steps)
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
