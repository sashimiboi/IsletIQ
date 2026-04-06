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
        let id = UUID()
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

    // Types we need
    private let shareTypes: Set<HKSampleType> = [
        HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!,
        HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
        HKQuantityType.quantityType(forIdentifier: .insulinDelivery)!,
    ]

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!,
        HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
        HKQuantityType.quantityType(forIdentifier: .insulinDelivery)!,
        HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
    ]

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
        let date = Date()
        let metadata: [String: Any] = [HKMetadataKeyFoodType: name]

        var samples: [HKQuantitySample] = []

        if carbs > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
                quantity: HKQuantity(unit: .gram(), doubleValue: carbs),
                start: date, end: date, metadata: metadata
            ))
        }
        if calories > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: date, end: date, metadata: metadata
            ))
        }
        if protein > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!,
                quantity: HKQuantity(unit: .gram(), doubleValue: protein),
                start: date, end: date, metadata: metadata
            ))
        }
        if fat > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!,
                quantity: HKQuantity(unit: .gram(), doubleValue: fat),
                start: date, end: date, metadata: metadata
            ))
        }

        guard !samples.isEmpty else { return }

        do {
            try await store.save(samples)
            print("HealthKit: logged \(name) - \(carbs)g carbs, \(calories) kcal")
            // Refresh meals list
            await fetchRecentMeals()
            await fetchRecentMeals()
        } catch {
            print("HealthKit save failed: \(error)")
        }
    }

    // MARK: - Log Glucose

    func logGlucose(value: Double, date: Date = .now) async {
        let sample = HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
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
        let insulinType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery)!
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

    func fetchRecentMeals() async {
        guard let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let calType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now, options: .strictStartDate)
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
                    return MealEntry(name: name, carbs: carbs, calories: matchedCals, date: sample.startDate, sample: sample)
                }

                Task { @MainActor in
                    self.recentMeals = meals
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

    func fetchLastSleep() async {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let startDate = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 100,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume()
                    return
                }

                // Group samples into sleep sessions based on time gaps
                // A gap of > 60 min between samples means a new session
                let sorted = samples.sorted { $0.startDate < $1.startDate }
                var sessions: [[HKCategorySample]] = []
                var currentSession: [HKCategorySample] = []

                for sample in sorted {
                    // Skip "inBed" samples, only use actual sleep stages
                    guard sample.value != HKCategoryValueSleepAnalysis.inBed.rawValue else { continue }

                    if let last = currentSession.last {
                        let gap = sample.startDate.timeIntervalSince(last.endDate)
                        if gap > 3600 { // > 1 hour gap = new session
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

                // Find the most recent session that's at least 2 hours (ignore short naps)
                guard let nightSession = sessions.last(where: { session in
                    let totalMin = session.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60.0 }
                    return totalMin >= 120
                }) ?? sessions.last else {
                    continuation.resume()
                    return
                }

                // Process only the selected session
                var totalSleep = 0.0
                var deep = 0.0
                var rem = 0.0
                var core = 0.0
                var awake = 0.0
                var earliest = Date.distantFuture
                var latest = Date.distantPast
                var segments: [SleepSegment] = []

                for sample in nightSession {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    if sample.startDate < earliest { earliest = sample.startDate }
                    if sample.endDate > latest { latest = sample.endDate }

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deep += duration; totalSleep += duration
                        segments.append(SleepSegment(stage: .deep, start: sample.startDate, end: sample.endDate))
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        rem += duration; totalSleep += duration
                        segments.append(SleepSegment(stage: .rem, start: sample.startDate, end: sample.endDate))
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        core += duration; totalSleep += duration
                        segments.append(SleepSegment(stage: .core, start: sample.startDate, end: sample.endDate))
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        core += duration; totalSleep += duration
                        segments.append(SleepSegment(stage: .core, start: sample.startDate, end: sample.endDate))
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awake += duration
                        segments.append(SleepSegment(stage: .awake, start: sample.startDate, end: sample.endDate))
                    default:
                        break
                    }
                }

                if totalSleep > 0 {
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
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Fetch Steps & Active Calories

    func fetchActivityToday() async {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: .now, options: .strictStartDate)

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
                var hourly: [(hour: Int, steps: Int)] = []
                results?.enumerateStatistics(from: startOfDay, to: .now) { stats, _ in
                    let hour = cal.component(.hour, from: stats.startDate)
                    let steps = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    hourly.append((hour: hour, steps: steps))
                }
                Task { @MainActor in
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
                var daily: [(date: Date, steps: Int)] = []
                results?.enumerateStatistics(from: sevenDaysAgo, to: .now) { stats, _ in
                    let steps = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    daily.append((date: stats.startDate, steps: steps))
                }
                Task { @MainActor in
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
                var hourly: [(hour: Int, cals: Double)] = []
                results?.enumerateStatistics(from: startOfDay, to: .now) { stats, _ in
                    let hour = cal.component(.hour, from: stats.startDate)
                    let cals = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    hourly.append((hour: hour, cals: cals))
                }
                Task { @MainActor in
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
                var daily: [(date: Date, cals: Double)] = []
                results?.enumerateStatistics(from: thirtyDaysAgo, to: .now) { stats, _ in
                    let cals = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    daily.append((date: stats.startDate, cals: cals))
                }
                Task { @MainActor in
                    self.weeklyCals = daily
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Fetch All Health Data

    func fetchAll() async {
        await fetchRecentMeals()
        await fetchLastSleep()
        await fetchActivityToday()
    }

    // MARK: - Observe New Food Entries

    func startObservingMeals(onChange: @escaping () -> Void) {
        let foodType = HKCorrelationType.correlationType(forIdentifier: .food)!
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
