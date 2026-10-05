import Foundation
import HealthKit

let weeklyZone2GoalMinutes = 120

struct Zone2Range: Equatable {
    let lowerBPM: Int
    let upperBPM: Int

    init?(lowerBPM: Int, upperBPM: Int) {
        guard (40...219).contains(lowerBPM),
              (41...220).contains(upperBPM),
              lowerBPM < upperBPM else { return nil }
        self.lowerBPM = lowerBPM
        self.upperBPM = upperBPM
    }

    func contains(_ bpm: Double) -> Bool {
        bpm >= Double(lowerBPM) && bpm <= Double(upperBPM)
    }
}

struct WeeklyZone2Progress: Equatable {
    let minutes: Int
    let goalMinutes: Int

    init(minutes: Int, goalMinutes: Int = weeklyZone2GoalMinutes) {
        self.minutes = max(minutes, 0)
        self.goalMinutes = max(goalMinutes, 1)
    }

    var cappedFraction: Double {
        min(Double(minutes) / Double(goalMinutes), 1)
    }
}

enum Zone2ProgressState: Equatable {
    case loading
    case needsRange
    case ready(WeeklyZone2Progress)
    case unavailable
}

struct Zone2HeartRateSample {
    let date: Date
    let bpm: Double
}

enum Zone2Calculator {
    static func estimatedRange(
        dateOfBirth: DateComponents,
        restingBPM: Double,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Zone2Range? {
        guard let birthDate = calendar.date(from: dateOfBirth),
              let age = calendar.dateComponents([.year], from: birthDate, to: now).year,
              (13...120).contains(age),
              (30...150).contains(restingBPM) else { return nil }

        let maximumBPM = 208 - (0.7 * Double(age))
        let reserve = maximumBPM - restingBPM
        guard reserve > 0 else { return nil }

        return Zone2Range(
            lowerBPM: Int((restingBPM + 0.60 * reserve).rounded()),
            upperBPM: Int((restingBPM + 0.70 * reserve).rounded())
        )
    }

    static func minutes(
        workoutIntervals: [DateInterval],
        samples: [Zone2HeartRateSample],
        range: Zone2Range,
        within week: DateInterval,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        let intervals = mergedIntervals(workoutIntervals, clippedTo: week)
        guard !intervals.isEmpty else { return 0 }

        var buckets: [Date: [Double]] = [:]
        for sample in samples where intervals.contains(where: {
            sample.date >= $0.start && sample.date < $0.end
        }) {
            guard let minute = calendar.dateInterval(of: .minute, for: sample.date)?.start else {
                continue
            }
            buckets[minute, default: []].append(sample.bpm)
        }

        return buckets.values.reduce(into: 0) { total, readings in
            let average = readings.reduce(0, +) / Double(readings.count)
            if range.contains(average) { total += 1 }
        }
    }

    private static func mergedIntervals(
        _ intervals: [DateInterval],
        clippedTo bounds: DateInterval
    ) -> [DateInterval] {
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, bounds.start)
            let end = min(interval.end, bounds.end)
            return start < end ? DateInterval(start: start, end: end) : nil
        }
        .sorted { $0.start < $1.start }

        return clipped.reduce(into: []) { merged, interval in
            guard let last = merged.last else {
                merged.append(interval)
                return
            }
            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
    }
}

extension SettingsStore {
    static let zone2LowerBPMKey = "zone2LowerBPM"
    static let zone2UpperBPMKey = "zone2UpperBPM"

    static var zone2Range: Zone2Range? {
        get {
            Zone2Range(
                lowerBPM: defaults.integer(forKey: zone2LowerBPMKey),
                upperBPM: defaults.integer(forKey: zone2UpperBPMKey)
            )
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: zone2LowerBPMKey)
                defaults.removeObject(forKey: zone2UpperBPMKey)
                return
            }
            defaults.set(newValue.lowerBPM, forKey: zone2LowerBPMKey)
            defaults.set(newValue.upperBPM, forKey: zone2UpperBPMKey)
        }
    }
}

final class Zone2ProgressService {
    static let shared = Zone2ProgressService()

    private let store = HKHealthStore()
    private let heartRateType = HKQuantityType(.heartRate)
    private let restingHeartRateType = HKQuantityType(.restingHeartRate)

    static var authorizationTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth),
        ]
    }

    private init() {}

    func estimatedRange(
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) async throws -> Zone2Range? {
        let dateOfBirth = try store.dateOfBirthComponents()
        let lookback = calendar.date(byAdding: .year, value: -1, to: now)
        let predicate = HKQuery.predicateForSamples(withStart: lookback, end: now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [
                .quantitySample(type: restingHeartRateType, predicate: predicate)
            ],
            sortDescriptors: []
        )
        let restingSamples = try await descriptor.result(for: store)
        guard let latest = restingSamples.max(by: { $0.startDate < $1.startDate }) else {
            return nil
        }
        let restingBPM = latest.quantity.doubleValue(
            for: HKUnit.count().unitDivided(by: .minute())
        )
        return Zone2Calculator.estimatedRange(
            dateOfBirth: dateOfBirth,
            restingBPM: restingBPM,
            now: now,
            calendar: calendar
        )
    }

    func weeklyProgress(
        range: Zone2Range,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) async throws -> WeeklyZone2Progress {
        guard let fullWeek = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return WeeklyZone2Progress(minutes: 0)
        }
        let week = DateInterval(start: fullWeek.start, end: min(fullWeek.end, now))
        let datePredicate = HKQuery.predicateForSamples(
            withStart: week.start,
            end: week.end
        )

        let workoutDescriptor = HKSampleQueryDescriptor(
            predicates: [.workout(datePredicate)],
            sortDescriptors: []
        )
        async let workouts = workoutDescriptor.result(for: store)

        let heartRateDescriptor = HKSampleQueryDescriptor(
            predicates: [
                .quantitySample(type: heartRateType, predicate: datePredicate)
            ],
            sortDescriptors: []
        )
        async let heartRates = heartRateDescriptor.result(for: store)

        let workoutIntervals = try await workouts.map {
            DateInterval(start: $0.startDate, end: $0.endDate)
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples = try await heartRates.map {
            Zone2HeartRateSample(
                date: $0.startDate,
                bpm: $0.quantity.doubleValue(for: unit)
            )
        }

        return WeeklyZone2Progress(
            minutes: Zone2Calculator.minutes(
                workoutIntervals: workoutIntervals,
                samples: samples,
                range: range,
                within: week,
                calendar: calendar
            )
        )
    }
}
