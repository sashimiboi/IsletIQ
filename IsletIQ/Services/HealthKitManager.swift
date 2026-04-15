import Foundation
import HealthKit

enum SleepStage: String {
    case deep = "Deep"
    case rem = "REM"
    case core = "Core"
    case awake = "Awake"

    var depth: Int { // lower = deeper sleep (for y-axis)
        switch self {
        case .awake: 0
        case .rem: 1
        case .core: 2
        case .deep: 3
        }
    }
}

struct SleepSegment: Identifiable {
    let id = UUID()
    let stage: SleepStage
    let start: Date
    let end: Date
    var durationMinutes: Double { end.timeIntervalSince(start) / 60.0 }
}

struct SleepData {
    let bedtime: Date
    let wakeTime: Date
    let totalMinutes: Double
    let deepMinutes: Double
    let remMinutes: Double
    let coreMinutes: Double
    let awakeMinutes: Double
    var segments: [SleepSegment] = []

    var totalHours: Double { totalMinutes / 60.0 }
    var quality: String {
        if totalHours >= 7.5 { return "Good" }
        if totalHours >= 6 { return "Fair" }
        return "Poor"
    }
}

@Observable
final class HealthKitManager {
    let store = HKHealthStore()
    var isAuthorized = false
    var recentMeals: [MealEntry] = []

    struct MealEntry: Identifiable {
        let id: UUID
        let name: String
        let carbs: Double
        let calories: Double
        let date: Date
        let sample: HKSample? // Keep reference for deletion
    }
    var lastSleep: SleepData?
    var stepsToday: Int = 0
    var hourlySteps: [(hour: Int, steps: Int)] = []
    var weeklySteps: [(date: Date, steps: Int)] = []
    var hourlyCals: [(hour: Int, cals: Double)] = []
    var weeklyCals: [(date: Date, cals: Double)] = []
    var activeCaloriesToday: Double = 0

    // Heart rate
    var currentHeartRate: Int = 0      // most recent sample
    var restingHeartRate: Int = 0      // today's resting HR
    var lastHeartRateTime: Date?
    var heartRateHourly: [(date: Date, value: Double)] = []  // hourly avg today
    var heartRateDaily: [(date: Date, value: Double)] = []   // daily avg last 30d

    // HRV (heart rate variability, SDNN in ms)
    var hrvLatest: Double = 0
    var hrvLastDate: Date?
    var hrvDaily: [(date: Date, value: Double)] = []         // last 30d

    // VO2 Max (ml/kg·min)
    var vo2MaxLatest: Double = 0
    var vo2MaxLastDate: Date?
    var vo2MaxHistory: [(date: Date, value: Double)] = []    // last 90d

    // Blood Pressure (mmHg)
    var bpSystolic: Int = 0
    var bpDiastolic: Int = 0
    var bpLastDate: Date?
    var bpHistory: [(date: Date, sys: Double, dia: Double)] = []  // last 30d

    // Body Temperature (Celsius)
    var bodyTempLatest: Double = 0
    var bodyTempLastDate: Date?
    var bodyTempHistory: [(date: Date, value: Double)] = []  // last 30d

    // Blood Oxygen / SpO2 (0..1 fraction, displayed as %)
    var spo2Latest: Double = 0
    var spo2LastDate: Date?
    var spo2History: [(date: Date, value: Double)] = []  // last 30d, stored as percentage

    // Insulin data from HealthKit (Omnipod writes here)
    struct InsulinEntry: Identifiable {
        let id = UUID()
        let units: Double
        let isBasal: Bool
        let date: Date
    }
    var recentBoluses: [InsulinEntry] = []
    var totalBasalToday: Double = 0
    var totalBolusToday: Double = 0
    var basalRateEstimate: Double = 0  // estimated u/hr from today's delivery
    var lastBolusUnits: Double = 0
    var lastBolusTime: Date?

    // Types we need. Built defensively with compactMap so devices missing
    // any specific type (older watch hardware, iPad without health) skip
    // it instead of crashing on a force unwrap.
    private let shareTypes: Set<HKSampleType> = {
        let ids: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed,
            .dietaryCarbohydrates,
            .dietaryProtein,
            .dietaryFatTotal,
            .bloodGlucose,
            .insulinDelivery,
        ]
        return Set(ids.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }()

    private let readTypes: Set<HKObjectType> = {
        let quantityIds: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed,
            .dietaryCarbohydrates,
            .dietaryProtein,
            .dietaryFatTotal,
            .bloodGlucose,
            .insulinDelivery,
            .stepCount,
            .activeEnergyBurned,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .vo2Max,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
            .bodyTemperature,
            .oxygenSaturation,
        ]
        let categoryIds: [HKCategoryTypeIdentifier] = [
            .sleepAnalysis,
        ]
        let quantities = quantityIds.compactMap { HKQuantityType.quantityType(forIdentifier: $0) as HKObjectType? }
        let categories = categoryIds.compactMap { HKCategoryType.categoryType(forIdentifier: $0) as HKObjectType? }
        return Set(quantities + categories)
    }()

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available on this device")
            return
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            await MainActor.run { isAuthorized = true }
        } catch {
            print("HealthKit auth failed: \(error)")
            // Try read-only if share fails
            do {
                try await store.requestAuthorization(toShare: [], read: readTypes)
                await MainActor.run { isAuthorized = true }
            } catch {
                print("HealthKit read-only auth also failed: \(error)")
            }
        }
    }

    // MARK: - Log Meal

    func logMeal(name: String, calories: Double, carbs: Double, protein: Double, fat: Double) async {
        // Skip if a meal with the same name was already logged today (prevents agent re-logging)
        let alreadyLogged = recentMeals.contains { existing in
            existing.name.lowercased() == name.lowercased() &&
            Calendar.current.isDateInToday(existing.date)
        }
        if alreadyLogged {
            print("HealthKit: skipping \(name), already logged today")
            return
        }

        // Bounds checking: no negative values, max 10000 kcal / 2000g macros
        let calories = min(max(calories, 0), 10000)
        let carbs = min(max(carbs, 0), 2000)
        let protein = min(max(protein, 0), 2000)
        let fat = min(max(fat, 0), 2000)

        let date = Date()
        let metadata: [String: Any] = [HKMetadataKeyFoodType: name]

        var samples: [HKQuantitySample] = []

        if carbs > 0, let type = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .gram(), doubleValue: carbs),
                start: date, end: date, metadata: metadata
            ))
        }
        if calories > 0, let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: date, end: date, metadata: metadata
            ))
        }
        if protein > 0, let type = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .gram(), doubleValue: protein),
                start: date, end: date, metadata: metadata
            ))
        }
        if fat > 0, let type = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .gram(), doubleValue: fat),
                start: date, end: date, metadata: metadata
            ))
        }

        guard !samples.isEmpty else { return }

        do {
            try await store.save(samples)
            print("HealthKit: logged \(name), \(carbs)g carbs, \(calories) kcal")
            await fetchRecentMeals()
        } catch {
            print("HealthKit save failed: \(error)")
        }
    }

    // MARK: - Log Glucose

    func logGlucose(value: Double, date: Date = .now) async {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            print("HealthKit: blood glucose type not available on this device")
            return
        }
        let sample = HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: HKUnit(from: "mg/dL"), doubleValue: value),
            start: date, end: date
        )
        do {
            try await store.save(sample)
            print("HealthKit: logged glucose \(value) mg/dL")
        } catch {
            print("HealthKit glucose save failed: \(error)")
        }
    }

    // MARK: - Log Insulin

    func logInsulin(units: Double, date: Date = .now, isBasal: Bool = false) async {
        guard let insulinType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else {
            print("HealthKit: insulin delivery type not available on this device")
            return
        }
        let metadata: [String: Any] = [
            HKMetadataKeyInsulinDeliveryReason: isBasal
                ? HKInsulinDeliveryReason.basal.rawValue
                : HKInsulinDeliveryReason.bolus.rawValue
        ]
        let sample = HKQuantitySample(
            type: insulinType,
            quantity: HKQuantity(unit: .internationalUnit(), doubleValue: units),
            start: date, end: date,
            metadata: metadata
        )
        do {
            try await store.save(sample)
            print("HealthKit: logged \(units)u insulin (\(isBasal ? "basal" : "bolus"))")
        } catch {
            print("HealthKit insulin save failed: \(error)")
        }
    }

    // MARK: - Fetch Recent Meals (query carbs directly, not food correlations)

    func fetchRecentMeals(for date: Date = .now) async {
        guard let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let calType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: date)!
        let endDate: Date = Calendar.current.isDateInToday(date) ? .now : Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        // Fetch calorie samples first to build a lookup by timestamp
        let calSamples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: calType,
                predicate: predicate,
                limit: 50,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        // Build lookup: match calories to carbs by timestamp (within 2 seconds) and food name
        let calLookup: [(date: Date, name: String, cals: Double)] = calSamples.map { s in
            (date: s.startDate,
             name: s.metadata?[HKMetadataKeyFoodType] as? String ?? "",
             cals: s.quantity.doubleValue(for: .kilocalorie()))
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(
                sampleType: carbType,
                predicate: predicate,
                limit: 30,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let carbSamples = samples as? [HKQuantitySample] else {
                    continuation.resume()
                    return
                }

                let meals: [MealEntry] = carbSamples.map { sample in
                    let name = sample.metadata?[HKMetadataKeyFoodType] as? String ?? "Meal"
                    let carbs = sample.quantity.doubleValue(for: .gram())
                    // Find matching calorie entry by timestamp and name
                    let matchedCals = calLookup.first { cal in
                        abs(cal.date.timeIntervalSince(sample.startDate)) < 2 &&
                        (cal.name == name || cal.name.isEmpty || name == "Meal")
                    }?.cals ?? 0
                    return MealEntry(id: sample.uuid, name: name, carbs: carbs, calories: matchedCals, date: sample.startDate, sample: sample)
                }

                // Deduplicate: if two entries share the same name on the same day, keep only the earliest
                var deduped: [MealEntry] = []
                for meal in meals {
                    let isDupe = deduped.contains { existing in
                        existing.name == meal.name &&
                        Calendar.current.isDate(existing.date, inSameDayAs: meal.date)
                    }
                    if !isDupe { deduped.append(meal) }
                }

                let finalDeduped = deduped
                Task { @MainActor [finalDeduped] in
                    self.recentMeals = finalDeduped
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Delete Meal

    func deleteMeal(_ meal: MealEntry) async {
        guard let sample = meal.sample else { return }
        do {
            try await store.delete(sample)
            await fetchRecentMeals()
            print("HealthKit: deleted meal \(meal.name)")
        } catch {
            print("HealthKit delete failed: \(error)")
        }
    }

    // MARK: - Fetch Sleep

    func fetchLastSleep(for date: Date = .now) async {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            print("HealthKit: sleep analysis type not available on this device")
            return
        }
        // Look back 2 days from the target date to capture overnight sleep sessions
        let startDate = Calendar.current.date(byAdding: .day, value: -2, to: date)!
        let endDate: Date = Calendar.current.isDateInToday(date) ? .now : Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 200,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    print("[Sleep] No samples returned from HealthKit for \(date)")
                    Task { @MainActor in self.lastSleep = nil }
                    continuation.resume()
                    return
                }

                // Debug: log what HealthKit returned
                let srcCounts = Dictionary(grouping: samples, by: { $0.sourceRevision.source.bundleIdentifier })
                    .mapValues { $0.count }
                print("[Sleep] \(samples.count) total samples from sources: \(srcCounts)")
                let valueCounts = Dictionary(grouping: samples, by: { $0.value }).mapValues { $0.count }
                print("[Sleep] By type: \(valueCounts) (0=inBed, 1=asleepUnspecified, 2=awake, 3=core, 4=deep, 5=REM)")

                // Filter out inBed samples first, keep only actual sleep stages
                let allStages = samples.filter { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue }
                print("[Sleep] \(allStages.count) sleep stage samples after removing inBed")

                // Pick one source for consistency (avoid double-counting overlapping sources)
                // Select based on sleep stage sample count, not total (inBed inflates Apple Watch count)
                var bySource: [String: [HKCategorySample]] = [:]
                for s in allStages {
                    let src = s.sourceRevision.source.bundleIdentifier
                    bySource[src, default: []].append(s)
                }
                let stageSrcCounts = bySource.mapValues { $0.count }
                print("[Sleep] Stage samples by source: \(stageSrcCounts)")
                let sleepSamples: [HKCategorySample]
                if let sw = bySource.first(where: { $0.key.localizedCaseInsensitiveContains("sleepwatch") })?.value {
                    print("[Sleep] Using SleepWatch source (\(sw.count) stages)")
                    sleepSamples = sw.sorted { $0.startDate < $1.startDate }
                } else if let best = bySource.max(by: { $0.value.count < $1.value.count }) {
                    print("[Sleep] Using source \(best.key) (\(best.value.count) stages)")
                    sleepSamples = best.value.sorted { $0.startDate < $1.startDate }
                } else {
                    print("[Sleep] Using all sources combined")
                    sleepSamples = allStages.sorted { $0.startDate < $1.startDate }
                }

                // Group into sessions based on time gaps > 1 hour
                var sessions: [[HKCategorySample]] = []
                var currentSession: [HKCategorySample] = []

                for sample in sleepSamples {
                    if let last = currentSession.last {
                        let gap = sample.startDate.timeIntervalSince(last.endDate)
                        if gap > 3600 {
                            if !currentSession.isEmpty { sessions.append(currentSession) }
                            currentSession = [sample]
                        } else {
                            currentSession.append(sample)
                        }
                    } else {
                        currentSession.append(sample)
                    }
                }
                if !currentSession.isEmpty { sessions.append(currentSession) }

                // Prefer session whose wake time falls on the selected day
                // Fall back to most recent session >= 2 hours, then any session
                let sessionForDay = sessions.last(where: { session in
                    guard let last = session.last else { return false }
                    return Calendar.current.isDate(last.endDate, inSameDayAs: date)
                })
                let longSession = sessions.last(where: { session in
                    let totalMin = session.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60.0 }
                    return totalMin >= 120
                })
                guard let nightSession = sessionForDay ?? longSession ?? sessions.last else {
                    Task { @MainActor in self.lastSleep = nil }
                    continuation.resume()
                    return
                }
                print("[Sleep] Picked session: \(sessionForDay != nil ? "day-match" : longSession != nil ? "long" : "last"), \(nightSession.count) samples")

                // Deduplicate overlapping time ranges (multiple sources can write the same period)
                // Walk through sorted segments and merge/skip overlaps
                var merged: [(value: Int, start: Date, end: Date)] = []
                for sample in nightSession {
                    let start = sample.startDate
                    let end = sample.endDate
                    if let last = merged.last, start < last.end {
                        // Overlapping: skip if fully covered, trim if partial
                        if end <= last.end { continue }
                        merged.append((value: sample.value, start: last.end, end: end))
                    } else {
                        merged.append((value: sample.value, start: start, end: end))
                    }
                }

                // Process deduplicated segments
                var totalSleep = 0.0
                var deep = 0.0
                var rem = 0.0
                var core = 0.0
                var awake = 0.0
                var earliest = Date.distantFuture
                var latest = Date.distantPast
                var segments: [SleepSegment] = []

                for seg in merged {
                    let duration = seg.end.timeIntervalSince(seg.start) / 60.0
                    if seg.start < earliest { earliest = seg.start }
                    if seg.end > latest { latest = seg.end }

                    switch seg.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deep += duration; totalSleep += duration
                        segments.append(SleepSegment(stage: .deep, start: seg.start, end: seg.end))
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        rem += duration; totalSleep += duration
                        segments.append(SleepSegment(stage: .rem, start: seg.start, end: seg.end))
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        core += duration; totalSleep += duration
                        segments.append(SleepSegment(stage: .core, start: seg.start, end: seg.end))
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        core += duration; totalSleep += duration
                        segments.append(SleepSegment(stage: .core, start: seg.start, end: seg.end))
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awake += duration
                        segments.append(SleepSegment(stage: .awake, start: seg.start, end: seg.end))
                    default:
                        break
                    }
                }

                // Only show sleep if wake time falls on the selected date
                // (sleep from 11pm Mon → 7am Tue belongs to Tuesday)
                let wakeOnSelectedDay = Calendar.current.isDate(latest, inSameDayAs: date)
                // For today, also accept sleep that ended within the last 12 hours
                print("[Sleep] Sessions: \(sessions.count), selected \(nightSession.count) samples, bed=\(earliest), wake=\(latest)")
                print("[Sleep] totalSleep=\(Int(totalSleep))min, date=\(date), wakeOnDay=\(wakeOnSelectedDay)")
                let isRecent = Calendar.current.isDateInToday(date) && abs(latest.timeIntervalSinceNow) < 43200

                if totalSleep > 0 && (wakeOnSelectedDay || isRecent) {
                    let sleep = SleepData(
                        bedtime: earliest,
                        wakeTime: latest,
                        totalMinutes: totalSleep,
                        deepMinutes: deep,
                        remMinutes: rem,
                        coreMinutes: core,
                        awakeMinutes: awake,
                        segments: segments.sorted { $0.start < $1.start }
                    )
                    Task { @MainActor in
                        self.lastSleep = sleep
                        continuation.resume()
                    }
                } else {
                    Task { @MainActor in
                        self.lastSleep = nil
                        continuation.resume()
                    }
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Fetch Steps & Active Calories

    func fetchActivityToday(for date: Date = .now) async {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endDate: Date = Calendar.current.isDateInToday(date) ? .now : Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endDate, options: .strictStartDate)

        // Steps
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                    let steps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    Task { @MainActor in
                        self.stepsToday = steps
                        continuation.resume()
                    }
                }
                store.execute(query)
            }
        }

        // Active calories
        if let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let query = HKStatisticsQuery(quantityType: calType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                    let cals = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    Task { @MainActor in
                        self.activeCaloriesToday = cals
                        continuation.resume()
                    }
                }
                store.execute(query)
            }
        }
    }

    // MARK: - Fetch Hourly Steps (for detail chart)

    func fetchHourlySteps() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: startOfDay, end: .now),
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: DateComponents(hour: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                let hourly: [(hour: Int, steps: Int)] = (results?.statistics() ?? []).map { stats in
                    let hour = cal.component(.hour, from: stats.startDate)
                    let steps = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    return (hour: hour, steps: steps)
                }
                Task { @MainActor [hourly] in
                    self.hourlySteps = hourly
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Fetch Weekly Steps (for 7-day chart)

    func fetchWeeklySteps() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let cal = Calendar.current
        let sevenDaysAgo = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: .now))!

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: sevenDaysAgo, end: .now),
                options: .cumulativeSum,
                anchorDate: sevenDaysAgo,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                let daily: [(date: Date, steps: Int)] = (results?.statistics() ?? []).map { stats in
                    let steps = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    return (date: stats.startDate, steps: steps)
                }
                Task { @MainActor [daily] in
                    self.weeklySteps = daily
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Fetch Hourly Calories

    func fetchHourlyCals() async {
        guard let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: calType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: startOfDay, end: .now),
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: DateComponents(hour: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                let hourly: [(hour: Int, cals: Double)] = (results?.statistics() ?? []).map { stats in
                    let hour = cal.component(.hour, from: stats.startDate)
                    let cals = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    return (hour: hour, cals: cals)
                }
                Task { @MainActor [hourly] in
                    self.hourlyCals = hourly
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    func fetchWeeklyCals() async {
        guard let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: .now))!

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: calType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: .now),
                options: .cumulativeSum,
                anchorDate: thirtyDaysAgo,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                let daily: [(date: Date, cals: Double)] = (results?.statistics() ?? []).map { stats in
                    let cals = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    return (date: stats.startDate, cals: cals)
                }
                Task { @MainActor [daily] in
                    self.weeklyCals = daily
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Fetch Heart Rate

    func fetchHeartRate(for date: Date = .now) async {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endDate: Date = Calendar.current.isDateInToday(date) ? .now : Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        // Most recent heart rate sample (last 30 min)
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let recentStart = max(startOfDay, Date().addingTimeInterval(-1800))
            let predicate = HKQuery.predicateForSamples(withStart: recentStart, end: endDate, options: .strictStartDate)
            let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 1, sortDescriptors: [sortDesc]) { _, samples, _ in
                    let sample = (samples as? [HKQuantitySample])?.first
                    let bpm = Int(sample?.quantity.doubleValue(for: bpmUnit) ?? 0)
                    let when = sample?.endDate
                    Task { @MainActor in
                        self.currentHeartRate = bpm
                        self.lastHeartRateTime = when
                        continuation.resume()
                    }
                }
                store.execute(query)
            }
        }

        // Resting heart rate (latest available, written once daily)
        if let restType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
            let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: endDate, options: .strictStartDate)
            let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let query = HKSampleQuery(sampleType: restType, predicate: predicate, limit: 1, sortDescriptors: [sortDesc]) { _, samples, _ in
                    let bpm = Int(((samples as? [HKQuantitySample])?.first?.quantity.doubleValue(for: bpmUnit)) ?? 0)
                    Task { @MainActor in
                        self.restingHeartRate = bpm
                        continuation.resume()
                    }
                }
                store.execute(query)
            }
        }

        print("[HealthKit] HR: \(currentHeartRate) bpm (resting \(restingHeartRate))")
    }

    // MARK: - Heart Rate History (hourly today + daily 30d)

    func fetchHeartRateHistory() async {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: startOfDay)!

        // Hourly today
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: hrType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: startOfDay, end: .now),
                options: .discreteAverage,
                anchorDate: startOfDay,
                intervalComponents: DateComponents(hour: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                let hourly: [(date: Date, value: Double)] = (results?.statistics() ?? []).compactMap { stats in
                    guard let avg = stats.averageQuantity()?.doubleValue(for: bpmUnit), avg > 0 else { return nil }
                    return (date: stats.startDate, value: avg)
                }
                Task { @MainActor [hourly] in
                    self.heartRateHourly = hourly
                    continuation.resume()
                }
            }
            store.execute(query)
        }

        // Daily 30d
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: hrType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: .now),
                options: .discreteAverage,
                anchorDate: thirtyDaysAgo,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                let daily: [(date: Date, value: Double)] = (results?.statistics() ?? []).compactMap { stats in
                    guard let avg = stats.averageQuantity()?.doubleValue(for: bpmUnit), avg > 0 else { return nil }
                    return (date: stats.startDate, value: avg)
                }
                Task { @MainActor [daily] in
                    self.heartRateDaily = daily
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Fetch HRV

    func fetchHRV() async {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        let msUnit = HKUnit.secondUnit(with: .milli)
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: .now))!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: .now, options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDesc]) { _, samples, _ in
                let arr = (samples as? [HKQuantitySample]) ?? []
                let series: [(date: Date, value: Double)] = arr.map { ($0.startDate, $0.quantity.doubleValue(for: msUnit)) }
                let latest = arr.last
                Task { @MainActor in
                    self.hrvDaily = series
                    self.hrvLatest = latest?.quantity.doubleValue(for: msUnit) ?? 0
                    self.hrvLastDate = latest?.startDate
                    continuation.resume()
                }
            }
            store.execute(query)
        }
        print("[HealthKit] HRV: \(String(format: "%.0f", hrvLatest))ms (\(hrvDaily.count) samples)")
    }

    // MARK: - Fetch VO2 Max

    func fetchVO2Max() async {
        guard let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return }
        let unit = HKUnit(from: "ml/kg*min")
        let cal = Calendar.current
        let ninetyDaysAgo = cal.date(byAdding: .day, value: -90, to: cal.startOfDay(for: .now))!
        let predicate = HKQuery.predicateForSamples(withStart: ninetyDaysAgo, end: .now, options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(sampleType: vo2Type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDesc]) { _, samples, _ in
                let arr = (samples as? [HKQuantitySample]) ?? []
                let series: [(date: Date, value: Double)] = arr.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
                let latest = arr.last
                Task { @MainActor in
                    self.vo2MaxHistory = series
                    self.vo2MaxLatest = latest?.quantity.doubleValue(for: unit) ?? 0
                    self.vo2MaxLastDate = latest?.startDate
                    continuation.resume()
                }
            }
            store.execute(query)
        }
        print("[HealthKit] VO2 Max: \(String(format: "%.1f", vo2MaxLatest)) ml/kg·min (\(vo2MaxHistory.count) samples)")
    }

    // MARK: - Fetch Blood Pressure

    func fetchBloodPressure() async {
        guard let sysType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diaType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else { return }
        let mmHg = HKUnit.millimeterOfMercury()
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: .now))!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: .now, options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        // Fetch both series independently, then pair by timestamp (within 5 sec)
        let sysSamples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: sysType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDesc]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        let diaSamples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: diaType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDesc]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }

        var pairs: [(date: Date, sys: Double, dia: Double)] = []
        for s in sysSamples {
            let sysVal = s.quantity.doubleValue(for: mmHg)
            if let d = diaSamples.first(where: { abs($0.startDate.timeIntervalSince(s.startDate)) < 5 }) {
                pairs.append((date: s.startDate, sys: sysVal, dia: d.quantity.doubleValue(for: mmHg)))
            }
        }

        let latest = pairs.last
        await MainActor.run {
            self.bpHistory = pairs
            self.bpSystolic = Int(latest?.sys ?? 0)
            self.bpDiastolic = Int(latest?.dia ?? 0)
            self.bpLastDate = latest?.date
            print("[HealthKit] BP: \(self.bpSystolic)/\(self.bpDiastolic) (\(pairs.count) readings)")
        }
    }

    // MARK: - Fetch Body Temperature

    func fetchBodyTemperature() async {
        guard let tempType = HKQuantityType.quantityType(forIdentifier: .bodyTemperature) else { return }
        let cUnit = HKUnit.degreeCelsius()
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: .now))!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: .now, options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(sampleType: tempType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDesc]) { _, samples, _ in
                let arr = (samples as? [HKQuantitySample]) ?? []
                let series: [(date: Date, value: Double)] = arr.map { ($0.startDate, $0.quantity.doubleValue(for: cUnit)) }
                let latest = arr.last
                Task { @MainActor in
                    self.bodyTempHistory = series
                    self.bodyTempLatest = latest?.quantity.doubleValue(for: cUnit) ?? 0
                    self.bodyTempLastDate = latest?.startDate
                    continuation.resume()
                }
            }
            store.execute(query)
        }
        print("[HealthKit] Body Temp: \(String(format: "%.1f", bodyTempLatest))°C (\(bodyTempHistory.count) samples)")
    }

    // MARK: - Fetch Blood Oxygen (SpO2)

    func fetchBloodOxygen() async {
        guard let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        let pctUnit = HKUnit.percent()
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: .now))!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: .now, options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(sampleType: spo2Type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDesc]) { _, samples, _ in
                let arr = (samples as? [HKQuantitySample]) ?? []
                // HealthKit returns 0..1; convert to percentage for display
                let series: [(date: Date, value: Double)] = arr.map { ($0.startDate, $0.quantity.doubleValue(for: pctUnit) * 100) }
                let latest = arr.last
                Task { @MainActor in
                    self.spo2History = series
                    self.spo2Latest = (latest?.quantity.doubleValue(for: pctUnit) ?? 0) * 100
                    self.spo2LastDate = latest?.startDate
                    continuation.resume()
                }
            }
            store.execute(query)
        }
        print("[HealthKit] SpO2: \(String(format: "%.0f", spo2Latest))% (\(spo2History.count) samples)")
    }

    // MARK: - Fetch All Health Data

    func fetchAll(for date: Date = .now) async {
        await fetchRecentMeals(for: date)
        await fetchLastSleep(for: date)
        await fetchActivityToday(for: date)
        await fetchHeartRate(for: date)
        await fetchHRV()
        await fetchVO2Max()
        await fetchBloodPressure()
        await fetchBodyTemperature()
        await fetchBloodOxygen()
        await fetchInsulinToday(for: date)
    }

    // MARK: - Insulin (Omnipod → HealthKit)

    func fetchInsulinToday(for date: Date = .now) async {
        guard let insulinType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else { return }
        let startOfDay = Calendar.current.startOfDay(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: date, options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: insulinType,
                predicate: predicate,
                limit: 100,
                sortDescriptors: [sortDesc]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        var boluses: [InsulinEntry] = []
        var basalTotal = 0.0
        var bolusTotal = 0.0

        for sample in samples {
            let units = sample.quantity.doubleValue(for: .internationalUnit())
            let reason = sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? Int
            let isBasal = reason == HKInsulinDeliveryReason.basal.rawValue
            if isBasal {
                basalTotal += units
            } else {
                bolusTotal += units
                boluses.append(InsulinEntry(units: units, isBasal: false, date: sample.startDate))
            }
        }

        let hoursElapsed = max(1, date.timeIntervalSince(startOfDay) / 3600.0)

        await MainActor.run {
            self.recentBoluses = boluses
            self.totalBasalToday = basalTotal
            self.totalBolusToday = bolusTotal
            self.basalRateEstimate = round((basalTotal / hoursElapsed) * 100) / 100
            self.lastBolusUnits = boluses.first?.units ?? 0
            self.lastBolusTime = boluses.first?.date
            print("[HealthKit] Insulin: \(boluses.count) boluses, \(String(format: "%.1f", basalTotal))u basal, \(String(format: "%.1f", bolusTotal))u bolus")
        }
    }

    // MARK: - Observe New Food Entries

    func startObservingMeals(onChange: @escaping () -> Void) {
        guard let foodType = HKCorrelationType.correlationType(forIdentifier: .food) else {
            print("HealthKit: food correlation type not available on this device")
            return
        }
        let query = HKObserverQuery(sampleType: foodType, predicate: nil) { _, completionHandler, error in
            if error == nil {
                onChange()
            }
            completionHandler()
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: foodType, frequency: .immediate) { _, _ in }
    }
}
