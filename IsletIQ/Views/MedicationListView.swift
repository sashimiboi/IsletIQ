import SwiftUI
import Charts

struct MedicationListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var medications: [Medication] = []
    @State private var history: [MedicationHistoryDay] = []
    @State private var historyError: String? = nil
    @State private var historyDays: Int = 14
    @State private var showAddMed = false
    @State private var editingMed: Medication?

    private let medClient = MedicationClient()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                MedicationAdherenceChart(history: history, days: $historyDays, errorMessage: historyError)
                    .onChange(of: historyDays) { _, _ in
                        Task { await loadHistory() }
                    }
                if medications.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "pills.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.textTertiary)
                        Text("No medications yet")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Text("Tap + to add your first medication")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(medications) { med in
                        MedicationCard(medication: med, onEdit: {
                            editingMed = med
                        }, onDelete: {
                            Task { await deleteMed(med.id) }
                        }, onToggle: {
                            Task { await toggleActive(med) }
                        })
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Theme.bg)
        .navigationTitle("Medications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddMed = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .sheet(isPresented: $showAddMed) {
            AddMedicationView(onSave: { Task { await load() } })
        }
        .sheet(item: $editingMed) { med in
            AddMedicationView(editing: med, onSave: { Task { await load() } })
        }
        .task {
            await load()
            await loadHistory()
        }
    }

    private func load() async {
        medications = await medClient.fetchMedications()
    }

    private func loadHistory() async {
        let result = await medClient.fetchHistory(days: historyDays)
        history = result.days
        historyError = result.errorMessage
    }

    private func deleteMed(_ id: Int) async {
        _ = await medClient.deleteMedication(id: id)
        await load()
    }

    private func toggleActive(_ med: Medication) async {
        _ = await medClient.updateMedication(id: med.id, isActive: !med.isActive)
        await load()
    }
}

// MARK: - Medication Card

struct MedicationCard: View {
    let medication: Medication
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: medication.categoryIcon)
                    .font(.caption)
                    .foregroundStyle(medication.isActive ? Theme.primary : Theme.textTertiary)
                Text(medication.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(medication.isActive ? Theme.textPrimary : Theme.textTertiary)
                Spacer()
                Menu {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button { onToggle() } label: {
                        Label(medication.isActive ? "Disable" : "Enable",
                              systemImage: medication.isActive ? "pause.circle" : "play.circle")
                    }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.textTertiary)
                        .padding(6)
                }
            }

            HStack(spacing: 12) {
                if !medication.dosage.isEmpty {
                    Label(medication.dosage, systemImage: "pills.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Label(medication.cadenceLabel, systemImage: medication.cadenceIcon)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if !medication.scheduleTimes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(medication.scheduleTimes, id: \.self) { time in
                        Text(MedicationTimeFormatter.display(time))
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.primary.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .opacity(medication.isActive ? 1 : 0.5)
        .card()
    }
}

// MARK: - Adherence Chart

enum AdherenceChartMode: String, CaseIterable, Identifiable {
    case percent, count
    var id: String { rawValue }
    var label: String {
        switch self {
        case .percent: return "Percent"
        case .count: return "Count"
        }
    }
}

struct MedicationAdherenceChart: View {
    let history: [MedicationHistoryDay]
    @Binding var days: Int
    var errorMessage: String? = nil
    @State private var mode: AdherenceChartMode = .percent
    @State private var selectedDate: Date? = nil

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private func parse(_ s: String) -> Date {
        Self.isoFormatter.date(from: s) ?? Date()
    }

    private var totalTaken: Int {
        history.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.taken } }
    }

    private var totalExpected: Int {
        history.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.expected } }
    }

    private var adherencePct: Int {
        guard totalExpected > 0 else { return 0 }
        return Int(round(Double(totalTaken) / Double(totalExpected) * 100))
    }

    private func dayPct(_ day: MedicationHistoryDay) -> Double {
        let expected = day.entries.reduce(0) { $0 + $1.expected }
        let taken = day.entries.reduce(0) { $0 + $1.taken }
        guard expected > 0 else { return 0 }
        return Double(taken) / Double(expected) * 100
    }

    private func dayTakenCount(_ day: MedicationHistoryDay) -> Int {
        day.entries.reduce(0) { $0 + $1.taken }
    }

    private func dayExpectedCount(_ day: MedicationHistoryDay) -> Int {
        day.entries.reduce(0) { $0 + $1.expected }
    }

    private var maxCount: Int {
        history.map { dayExpectedCount($0) }.max() ?? 1
    }

    private func sameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }

    private var selectedDay: MedicationHistoryDay? {
        guard let selectedDate else { return nil }
        return history.first { sameDay(parse($0.date), selectedDate) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adherence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(adherencePct)%")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                SquareSegmented(selection: $days, options: [(1, "1d"), (7, "7d"), (14, "14d"), (30, "30d")])
            }

            HStack(spacing: 6) {
                SquareSegmented(
                    selection: $mode,
                    options: AdherenceChartMode.allCases.map { ($0, $0.label) }
                )
                Spacer()
            }

            if history.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: errorMessage == nil ? "chart.bar.xaxis" : "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(errorMessage == nil ? Theme.textTertiary : .orange)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Check Xcode console for details.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Text("No dose history yet")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text("Log a dose to start building your chart.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
            } else {
                Chart {
                    ForEach(history) { day in
                        let expectedTotal = dayExpectedCount(day)
                        let dimmed = selectedDate != nil && !sameDay(parse(day.date), selectedDate!)
                        ForEach(day.entries, id: \.medicationId) { entry in
                            let value: Double = {
                                switch mode {
                                case .percent:
                                    return expectedTotal > 0 ? Double(entry.taken) / Double(expectedTotal) * 100 : 0
                                case .count:
                                    return Double(entry.taken)
                                }
                            }()
                            BarMark(
                                x: .value("Day", parse(day.date), unit: .day),
                                y: .value(mode == .percent ? "Adherence" : "Taken", value)
                            )
                            .foregroundStyle(by: .value("Medication", entry.name))
                            .cornerRadius(2)
                            .opacity(dimmed ? 0.35 : 1)
                        }
                        if mode == .percent {
                            let missedPct = expectedTotal > 0
                                ? max(0.0, 100.0 - Double(dayTakenCount(day)) / Double(expectedTotal) * 100.0)
                                : 100.0
                            if missedPct > 0 {
                                BarMark(
                                    x: .value("Day", parse(day.date), unit: .day),
                                    y: .value("Missed", missedPct)
                                )
                                .foregroundStyle(Theme.textTertiary.opacity(0.2))
                                .cornerRadius(2)
                                .opacity(dimmed ? 0.35 : 1)
                            }
                        }
                    }

                    if mode == .percent, selectedDate == nil {
                        RuleMark(y: .value("Goal", 100))
                            .foregroundStyle(Theme.textTertiary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
                .chartYScale(domain: 0.0...(mode == .percent ? 110.0 : Double(max(1, maxCount))))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, days / 7))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        if mode == .percent, let pct = value.as(Double.self) {
                            AxisValueLabel {
                                Text("\(Int(pct))%").font(.caption2)
                            }
                        } else {
                            AxisValueLabel().font(.caption2)
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        selectedDate = nil
                                    }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if let plotFrame = proxy.plotFrame {
                                                let origin = geo[plotFrame].origin
                                                let x = value.location.x - origin.x
                                                if let date: Date = proxy.value(atX: x) {
                                                    let day = Calendar.current.startOfDay(for: date)
                                                    if history.contains(where: { sameDay(parse($0.date), day) }) {
                                                        selectedDate = day
                                                    }
                                                }
                                            }
                                        }
                                )

                            if let day = selectedDay, let plotFrame = proxy.plotFrame {
                                let plot = geo[plotFrame]
                                let barDate = parse(day.date)
                                let barX = proxy.position(forX: barDate) ?? 0
                                let tooltipWidth: CGFloat = 140
                                let pinnedX = min(max(barX + plot.minX - tooltipWidth / 2, 4),
                                                  geo.size.width - tooltipWidth - 4)

                                // Vertical line marker on the selected bar
                                Rectangle()
                                    .fill(Theme.textSecondary.opacity(0.4))
                                    .frame(width: 1)
                                    .frame(height: plot.height)
                                    .position(x: barX + plot.minX, y: plot.minY + plot.height / 2)

                                AdherenceChartTooltip(day: day, parse: parse, dayTaken: dayTakenCount(day), dayExpected: dayExpectedCount(day), dayPct: dayPct(day))
                                    .frame(width: tooltipWidth)
                                    .position(
                                        x: pinnedX + tooltipWidth / 2,
                                        y: max(plot.minY + 4, 0) + 30
                                    )
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .frame(height: 160)

                if let day = selectedDay {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(parse(day.date), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(dayTakenCount(day))/\(dayExpectedCount(day)) doses · \(Int(dayPct(day)))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                            Button {
                                selectedDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(day.entries, id: \.medicationId) { entry in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(entry.taken >= entry.expected ? Color.green : entry.taken > 0 ? .orange : Theme.textTertiary)
                                    .frame(width: 6, height: 6)
                                Text(entry.name)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text("\(entry.taken)/\(entry.expected)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .card()
    }
}

// MARK: - Chart Tooltip

struct AdherenceChartTooltip: View {
    let day: MedicationHistoryDay
    let parse: (String) -> Date
    let dayTaken: Int
    let dayExpected: Int
    let dayPct: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(parse(day.date), format: .dateTime.month(.abbreviated).day())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(dayTaken)/\(dayExpected) · \(Int(dayPct))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
            Divider().background(.white.opacity(0.2))
            ForEach(day.entries, id: \.medicationId) { entry in
                HStack(spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(entry.taken)/\(entry.expected)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

// MARK: - Square Segmented Control

struct SquareSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { (value, label) in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = value }
                } label: {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(selection == value ? .white : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selection == value ? Theme.primary : Theme.muted,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
