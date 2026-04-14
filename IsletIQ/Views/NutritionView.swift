import SwiftUI

struct NutritionView: View {
    var healthKit: HealthKitManager?
    @State private var showLogMeal = false
    @State private var activeMetric: HealthMetric? = nil
    @State private var isLoading = false
    @State private var todayMeds: [TodayMedication] = []
    @State private var showAddMed = false
    @State private var showMedList = false
    @State private var selectedDate: Date = .now
    private let medClient = MedicationClient()

    enum HealthMetric: String, Identifiable {
        case steps, calories, heartRate, hrv, vo2Max, bloodPressure, bodyTemp, bloodOxygen
        var id: String { rawValue }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Date selector
                dateStrip

                // Sleep
                sleepCard

                // Food & medication grouped right under sleep
                medicationsCard
                todaySummary

                // Health metrics grid (steps, HR, HRV, VO₂, BP, temp, SpO₂)
                activityCard

                // Quick log before the reference
                quickLogCard

                // Carb reference
                carbReferenceCard

                // Recent meals at the bottom
                recentMealsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .navigationTitle("Health")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showLogMeal = true } label: {
                    Image(systemName: "plus").font(.body.weight(.medium))
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .sheet(isPresented: $showLogMeal) {
            if let hk = healthKit {
                LogMealView(healthKit: hk)
            }
        }
        .sheet(isPresented: $showAddMed) {
            AddMedicationView(onSave: { Task { todayMeds = await medClient.fetchTodaySchedule() } })
        }
        .sheet(item: $activeMetric) { metric in
            metricSheet(for: metric)
        }
        .navigationDestination(isPresented: $showMedList) {
            MedicationListView()
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .onChange(of: selectedDate) {
            Task { await loadData() }
        }
    }

    // MARK: - Sleep Card

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sleep")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.primary)
                    Text("HealthKit")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if let sleep = healthKit?.lastSleep {
                HStack(spacing: 0) {
                    SleepStat(value: String(format: "%.1f", sleep.totalHours), unit: "hrs", label: "Total", color: Theme.primary)
                    Spacer()
                    SleepStat(value: sleep.quality, unit: "", label: "Quality", color: sleep.quality == "Good" ? Theme.normal : sleep.quality == "Fair" ? Theme.elevated : Theme.high)
                    Spacer()
                    SleepStat(value: String(format: "%.0f", sleep.deepMinutes), unit: "min", label: "Deep", color: Theme.teal)
                    Spacer()
                    SleepStat(value: String(format: "%.0f", sleep.remMinutes), unit: "min", label: "REM", color: Theme.primary)
                }

                // Sleep stages timeline chart
                if !sleep.segments.isEmpty {
                    SleepChartView(sleep: sleep)
                } else {
                    // Fallback: simple bar if no segment data
                    let total = max(1, sleep.totalMinutes + sleep.awakeMinutes)
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            if sleep.deepMinutes > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(red: 0.15, green: 0.2, blue: 0.55))
                                    .frame(width: geo.size.width * sleep.deepMinutes / total)
                            }
                            if sleep.coreMinutes > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(red: 0.25, green: 0.4, blue: 0.75))
                                    .frame(width: geo.size.width * sleep.coreMinutes / total)
                            }
                            if sleep.remMinutes > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(red: 0.4, green: 0.6, blue: 0.9))
                                    .frame(width: geo.size.width * sleep.remMinutes / total)
                            }
                            if sleep.awakeMinutes > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.5))
                                    .frame(width: geo.size.width * sleep.awakeMinutes / total)
                            }
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text(sleep.bedtime, format: .dateTime.hour().minute())
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Text(sleep.wakeTime, format: .dateTime.hour().minute())
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(Theme.textTertiary)
                    Text("No sleep data - make sure sleep tracking is on")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Activity Card

    private var activityCard: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let stepsVal = healthKit?.stepsToday ?? 0
        let calsVal = Int(healthKit?.activeCaloriesToday ?? 0)
        let hr = healthKit?.currentHeartRate ?? 0
        let restHr = healthKit?.restingHeartRate ?? 0
        let hrv = healthKit?.hrvLatest ?? 0
        let vo2 = healthKit?.vo2MaxLatest ?? 0
        let sys = healthKit?.bpSystolic ?? 0
        let dia = healthKit?.bpDiastolic ?? 0
        let temp = healthKit?.bodyTempLatest ?? 0
        let spo2 = healthKit?.spo2Latest ?? 0

        return LazyVGrid(columns: cols, spacing: 12) {
            metricTile(
                icon: "figure.walk",
                color: Theme.normal,
                value: "\(stepsVal)",
                label: "Steps",
                subtitle: stepsVal > 0 ? String(format: "%.1f mi", Double(stepsVal) * 0.0004) : nil
            ) { activeMetric = .steps }

            metricTile(
                icon: "flame.fill",
                color: Theme.elevated,
                value: "\(calsVal)",
                label: "Active Cal",
                subtitle: nil
            ) { activeMetric = .calories }

            metricTile(
                icon: "heart.fill",
                color: .pink,
                value: hr > 0 ? "\(hr)" : "--",
                label: "Heart Rate",
                subtitle: restHr > 0 ? "rest \(restHr) bpm" : "bpm"
            ) { activeMetric = .heartRate }

            metricTile(
                icon: "waveform.path.ecg",
                color: .purple,
                value: hrv > 0 ? "\(Int(hrv))" : "--",
                label: "HRV",
                subtitle: "ms (SDNN)"
            ) { activeMetric = .hrv }

            metricTile(
                icon: "lungs.fill",
                color: Theme.teal,
                value: vo2 > 0 ? String(format: "%.1f", vo2) : "--",
                label: "VO₂ Max",
                subtitle: "ml/kg·min"
            ) { activeMetric = .vo2Max }

            metricTile(
                icon: "heart.text.square.fill",
                color: .red,
                value: sys > 0 ? "\(sys)/\(dia)" : "--",
                label: "Blood Pressure",
                subtitle: "mmHg"
            ) { activeMetric = .bloodPressure }

            metricTile(
                icon: "thermometer.medium",
                color: .orange,
                value: temp > 0 ? String(format: "%.1f°", temp * 9 / 5 + 32) : "--",
                label: "Body Temp",
                subtitle: temp > 0 ? String(format: "%.1f°C", temp) : "°F"
            ) { activeMetric = .bodyTemp }

            metricTile(
                icon: "lungs",
                color: .blue,
                value: spo2 > 0 ? String(format: "%.0f%%", spo2) : "--",
                label: "Blood Oxygen",
                subtitle: "SpO₂"
            ) { activeMetric = .bloodOxygen }
        }
    }

    // MARK: - Metric Tile

    private func metricTile(
        icon: String,
        color: Color,
        value: String,
        label: String,
        subtitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                }

                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value == "--" ? "no data" : "\(value)\(subtitle.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens \(label) details")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Metric Sheet Builder

    @ViewBuilder
    private func metricSheet(for metric: HealthMetric) -> some View {
        switch metric {
        case .steps:
            StepsDetailView(healthKit: healthKit)
        case .calories:
            CaloriesDetailView(healthKit: healthKit)
        case .heartRate:
            HealthMetricDetailView(
                title: "Heart Rate",
                icon: "heart.fill",
                color: .pink,
                unit: "bpm",
                currentText: (healthKit?.currentHeartRate ?? 0) > 0 ? "\(healthKit!.currentHeartRate)" : "--",
                currentSubtitle: (healthKit?.restingHeartRate ?? 0) > 0 ? "Resting \(healthKit!.restingHeartRate) bpm" : nil,
                series: healthKit?.heartRateDaily ?? [],
                format: { String(format: "%.0f", $0) },
                goodRange: 60...100,
                fetch: { await healthKit?.fetchHeartRateHistory() }
            )
        case .hrv:
            HealthMetricDetailView(
                title: "Heart Rate Variability",
                icon: "waveform.path.ecg",
                color: .purple,
                unit: "ms (SDNN)",
                currentText: (healthKit?.hrvLatest ?? 0) > 0 ? "\(Int(healthKit!.hrvLatest))" : "--",
                currentSubtitle: healthKit?.hrvLastDate.map { dateLabel($0) },
                series: healthKit?.hrvDaily ?? [],
                format: { String(format: "%.0f", $0) },
                goodRange: nil,
                fetch: { await healthKit?.fetchHRV() }
            )
        case .vo2Max:
            HealthMetricDetailView(
                title: "VO₂ Max",
                icon: "lungs.fill",
                color: Theme.teal,
                unit: "ml/kg·min",
                currentText: (healthKit?.vo2MaxLatest ?? 0) > 0 ? String(format: "%.1f", healthKit!.vo2MaxLatest) : "--",
                currentSubtitle: healthKit?.vo2MaxLastDate.map { dateLabel($0) },
                series: healthKit?.vo2MaxHistory ?? [],
                format: { String(format: "%.1f", $0) },
                goodRange: nil,
                fetch: { await healthKit?.fetchVO2Max() }
            )
        case .bloodPressure:
            let bpData = healthKit?.bpHistory ?? []
            let sysSeries = bpData.map { (date: $0.date, value: $0.sys) }
            let diaSeries = bpData.map { (date: $0.date, value: $0.dia) }
            HealthMetricDetailView(
                title: "Blood Pressure",
                icon: "heart.text.square.fill",
                color: .red,
                unit: "mmHg",
                currentText: (healthKit?.bpSystolic ?? 0) > 0 ? "\(healthKit!.bpSystolic)/\(healthKit!.bpDiastolic)" : "--",
                currentSubtitle: healthKit?.bpLastDate.map { dateLabel($0) },
                series: sysSeries,
                series2: diaSeries,
                series2Label: "Diastolic",
                format: { String(format: "%.0f", $0) },
                goodRange: nil,
                fetch: { await healthKit?.fetchBloodPressure() }
            )
        case .bodyTemp:
            // Convert C → F for display
            let tempC = healthKit?.bodyTempLatest ?? 0
            let series = (healthKit?.bodyTempHistory ?? []).map { (date: $0.date, value: $0.value * 9 / 5 + 32) }
            HealthMetricDetailView(
                title: "Body Temperature",
                icon: "thermometer.medium",
                color: .orange,
                unit: "°F",
                currentText: tempC > 0 ? String(format: "%.1f°", tempC * 9 / 5 + 32) : "--",
                currentSubtitle: healthKit?.bodyTempLastDate.map { dateLabel($0) },
                series: series,
                format: { String(format: "%.1f°", $0) },
                goodRange: 97.0...99.0,
                fetch: { await healthKit?.fetchBodyTemperature() }
            )
        case .bloodOxygen:
            HealthMetricDetailView(
                title: "Blood Oxygen",
                icon: "lungs",
                color: .blue,
                unit: "% SpO₂",
                currentText: (healthKit?.spo2Latest ?? 0) > 0 ? String(format: "%.0f%%", healthKit!.spo2Latest) : "--",
                currentSubtitle: healthKit?.spo2LastDate.map { dateLabel($0) },
                series: healthKit?.spo2History ?? [],
                format: { String(format: "%.0f%%", $0) },
                goodRange: 95.0...100.0,
                fetch: { await healthKit?.fetchBloodOxygen() }
            )
        }
    }

    private func dateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Last reading: \(f.string(from: d))"
    }

    // MARK: - Medications Card

    private var medicationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "pills.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.primary)
                Text("Medications")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()

                let totalSlots = todayMeds.reduce(0) { $0 + $1.totalSlots }
                let takenSlots = todayMeds.reduce(0) { $0 + $1.takenCount }
                if totalSlots > 0 {
                    Text("\(takenSlots)/\(totalSlots)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(takenSlots == totalSlots ? .green : Theme.primary)
                }

                Button { showMedList = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(Theme.primary)
                }
                Button { showAddMed = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.primary)
                }
            }

            if todayMeds.isEmpty {
                Text("No medications — tap + to add")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(todayMeds) { med in
                    ForEach(med.scheduleTimes, id: \.self) { time in
                        let taken = med.isDoseTaken(at: time)
                        HStack(spacing: 10) {
                            Button {
                                if !taken {
                                    Task {
                                        _ = await medClient.logDose(medicationId: med.id, scheduledTime: time)
                                        todayMeds = await medClient.fetchTodaySchedule()
                                    }
                                }
                            } label: {
                                Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                                    .font(.body)
                                    .foregroundStyle(taken ? .green : Theme.textTertiary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(med.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(taken ? Theme.textTertiary : Theme.textPrimary)
                                    .strikethrough(taken)
                                if !med.dosage.isEmpty {
                                    Text(med.dosage)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }

                            Spacer()

                            Text(time)
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Today Summary

    private var todayMeals: [HealthKitManager.MealEntry] {
        healthKit?.recentMeals.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) } ?? []
    }

    private var todaySummary: some View {
        let meals = todayMeals
        let totalCarbs = meals.reduce(0.0) { $0 + $1.carbs }
        let totalCals = meals.reduce(0.0) { $0 + $1.calories }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isToday ? "Today" : selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                    Text("HealthKit")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            HStack(spacing: 0) {
                NutritionStat(value: "\(meals.count)", label: "Meals", icon: "fork.knife", color: Theme.primary)
                Spacer()
                NutritionStat(value: "\(Int(totalCarbs))g", label: "Carbs", icon: "leaf.fill", color: Theme.teal)
                Spacer()
                NutritionStat(value: "\(Int(totalCals))", label: "Cal Eaten", icon: "flame.fill", color: Theme.elevated)
                Spacer()
                NutritionStat(value: String(format: "%.1fu", totalCarbs / 13.0), label: "Insulin", icon: "drop.fill", color: Theme.primary)
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Quick Log

    private var quickLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Log")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Tap to log common items or use the Agent to estimate meals from a description or photo")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QuickMealChip(name: "Latte", carbs: 15, icon: "cup.and.saucer.fill") { await logQuick("Latte", carbs: 15, cals: 190, protein: 10, fat: 7) }
                    QuickMealChip(name: "Apple", carbs: 25, icon: "leaf.fill") { await logQuick("Apple", carbs: 25, cals: 95) }
                    QuickMealChip(name: "Juice Box", carbs: 22, icon: "drop.fill") { await logQuick("Juice Box", carbs: 22, cals: 90) }
                    QuickMealChip(name: "Glucose Tabs", carbs: 16, icon: "pills.fill") { await logQuick("Glucose Tabs", carbs: 16, cals: 60) }
                    QuickMealChip(name: "Protein Bar", carbs: 25, icon: "rectangle.fill") { await logQuick("Protein Bar", carbs: 25, cals: 200, protein: 20, fat: 8) }
                    QuickMealChip(name: "Banana", carbs: 27, icon: "leaf.fill") { await logQuick("Banana", carbs: 27, cals: 105) }
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Recent Meals

    private var recentMealsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Meals")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    Task { await healthKit?.fetchRecentMeals() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(Theme.primary)
                }
                .buttonStyle(.plain)
            }

            let meals = healthKit?.recentMeals ?? []

            if meals.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.title2)
                        .foregroundStyle(Theme.textTertiary)
                    Text("No meals logged yet")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Text("Log a meal or ask the Nutrition agent to estimate one")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(meals.prefix(10)) { meal in
                    MealRow(meal: meal, onDelete: {
                        Task { await healthKit?.deleteMeal(meal) }
                    })
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - Carb Reference

    private func logQuick(_ name: String, carbs: Double, cals: Double, protein: Double = 0, fat: Double = 0) async {
        await healthKit?.logMeal(name: name, calories: cals, carbs: carbs, protein: protein, fat: fat)
        await healthKit?.fetchAll()
    }

    // MARK: - Date Strip

    private var dateStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = (-6...0).map { calendar.date(byAdding: .day, value: $0, to: today)! }

        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDate = day }
                } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.short)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isSelected ? .white : Theme.textTertiary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 14, weight: isSelected ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(isSelected ? .white : Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isSelected ? Theme.primary : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
    }

    private func loadData() async {
        async let health: () = healthKit?.fetchAll(for: selectedDate) ?? ()
        async let meds = medClient.fetchTodaySchedule()
        _ = await health
        todayMeds = await meds
    }

    private var carbReferenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Carb Quick Reference")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            let foods: [(name: String, carbs: Int, bolus: String)] = [
                ("Slice of bread", 15, "1.2u"),
                ("Medium apple", 25, "1.9u"),
                ("Cup of rice", 45, "3.5u"),
                ("Banana", 27, "2.1u"),
                ("Glass of milk", 12, "0.9u"),
                ("Tortilla (flour)", 26, "2.0u"),
                ("Juice box", 22, "1.7u"),
                ("Glucose tabs (4)", 16, "1.2u"),
            ]

            ForEach(foods, id: \.name) { food in
                HStack {
                    Text(food.name)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(food.carbs)g")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.teal)
                    Text("→")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                    Text(food.bolus)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.primary)
                }
                .padding(.vertical, 2)
            }

            Text("Based on your I:C ratio 1:13")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 4)
        }
        .padding(20)
        .card()
    }
}

// MARK: - Supporting Views

struct SleepStat: View {
    let value: String
    let unit: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct NutritionStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct QuickMealChip: View {
    let name: String
    let carbs: Int
    let icon: String
    var onTap: (() async -> Void)?
    @State private var logged = false

    var body: some View {
        Button {
            Task {
                await onTap?()
                logged = true
                try? await Task.sleep(for: .seconds(2))
                logged = false
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: logged ? "checkmark.circle.fill" : icon)
                    .font(.caption)
                    .foregroundStyle(logged ? Theme.normal : Theme.teal)
                Text(name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(carbs)g")
                    .font(.system(size: 10).weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 72)
            .padding(.vertical, 10)
            .background(logged ? Theme.normal.opacity(0.08) : Theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(logged ? Theme.normal.opacity(0.3) : Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct MealRow: View {
    let meal: HealthKitManager.MealEntry
    var onDelete: (() -> Void)? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "fork.knife")
                .font(.caption)
                .foregroundStyle(Theme.teal)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(Int(meal.carbs))g carbs")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.teal)
                    if meal.calories > 0 {
                        Text("\(Int(meal.calories)) kcal")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(meal.date, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                Text(meal.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            if onDelete != nil {
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
        .alert("Delete Meal", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete?() }
        } message: {
            Text("Remove \"\(meal.name)\" from HealthKit?")
        }
    }
}

#Preview {
    NavigationStack {
        NutritionView()
    }
}
