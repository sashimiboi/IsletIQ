import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var readings: [GlucoseReading]
    @State private var selectedFilter: TimeFilter = .week

    private var filteredReadings: [GlucoseReading] {
        let cutoff: Date
        switch selectedFilter {
        case .today: cutoff = Calendar.current.startOfDay(for: .now)
        case .week: cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        case .month: cutoff = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        case .all: return readings
        }
        return readings.filter { $0.timestamp >= cutoff }
    }

    private var groupedByDay: [(String, [GlucoseReading])] {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        let grouped = Dictionary(grouping: filteredReadings) { fmt.string(from: $0.timestamp) }
        return grouped.sorted {
            ($0.value.first?.timestamp ?? .distantPast) > ($1.value.first?.timestamp ?? .distantPast)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Filter
                HStack(spacing: 0) {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = filter }
                        } label: {
                            Text(filter.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedFilter == filter ? .white : Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    selectedFilter == filter ? Theme.primary : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))

                // Summary
                if !filteredReadings.isEmpty {
                    summaryCard
                }

                // Groups
                readingsGroupList
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .navigationTitle("History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    @ViewBuilder
    private var readingsGroupList: some View {
        if groupedByDay.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.textTertiary)
                Text("No Readings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 60)
        } else {
            ForEach(groupedByDay, id: \.0) { day, dayReadings in
                VStack(alignment: .leading, spacing: 8) {
                    Text(day)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(dayReadings.enumerated()), id: \.element.id) { i, reading in
                            HistoryReadingRow(reading: reading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                            if i < dayReadings.count - 1 {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .card()
                }
            }
        }
    }

    private var summaryCard: some View {
        let vals = filteredReadings.map(\.value)
        let avg = vals.reduce(0, +) / max(1, vals.count)
        let lo = vals.min() ?? 0
        let hi = vals.max() ?? 0
        let tir = filteredReadings.filter { $0.value >= 70 && $0.value <= 180 }.count
        let tirPct = Int(Double(tir) / Double(max(1, vals.count)) * 100)

        return HStack {
            SummaryItem(label: "Average", value: "\(avg)", color: Theme.primary)
            Spacer()
            SummaryItem(label: "Low", value: "\(lo)", color: Theme.low)
            Spacer()
            SummaryItem(label: "High", value: "\(hi)", color: Theme.elevated)
            Spacer()
            SummaryItem(label: "TIR", value: "\(tirPct)%", color: Theme.normal)
        }
        .padding(20)
        .card()
    }
}

enum TimeFilter: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case all = "All"
}

struct SummaryItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct HistoryReadingRow: View {
    let reading: GlucoseReading
    private var color: Color { Theme.statusColor(reading.status) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: reading.trendArrow.symbol)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            Text("\(reading.value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text("mg/dL")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            if reading.mealTag != .none {
                Text(reading.mealTag.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Spacer()
            Text(reading.timestamp, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: GlucoseReading.self, inMemory: true)
}
