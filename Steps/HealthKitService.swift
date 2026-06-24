//
//  HealthKitService.swift
//  Steps
//
//  Shared between the app and the widget extension (same source file is a member
//  of both targets). HealthKit authorization granted to the app is shared with
//  its extensions, so the widget can read step data directly without an App Group.
//

import Foundation
import HealthKit

/// Daily step goal used to bucket grid intensity. GitHub-style "usage" is
/// measured relative to this fixed goal so colors mean the same thing every day.
let dailyStepGoal = 10_000

/// Maps a day's step total to an intensity level 0...4 (empty → full).
///
/// Buckets are quarters of the 10k goal so the green ramp reads like GitHub's
/// contribution graph:
///   0 steps → 0 (empty), 1–2500 → 1, 2501–5000 → 2, 5001–7500 → 3, 7501+ → 4.
func level(for steps: Int) -> Int {
    switch steps {
    case ..<1: return 0
    case ..<2_501: return 1
    case ..<5_001: return 2
    case ..<7_501: return 3
    default: return 4
    }
}

enum HealthKitError: Error {
    case notAvailable
    case noStepType
}

final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)

    private init() {}

    /// Requests read access to step count. Safe to call repeatedly; iOS only
    /// prompts the user the first time.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try await store.requestAuthorization(toShare: [], read: [stepType])
    }

    /// HealthKit deliberately hides whether *read* access was granted (to avoid
    /// leaking the absence of data). We treat "we got a non-zero read at least
    /// once" as authorized at the call sites; this only reports the explicit
    /// not-determined state so the UI can decide whether to show the prompt.
    var needsAuthorizationPrompt: Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return store.authorizationStatus(for: stepType) == .notDetermined
    }

    /// Total steps from local start-of-day until now.
    func todaySteps() async throws -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return try await sum(predicate: predicate)
    }

    /// Per-day step totals for the last `daysBack` days (including today),
    /// keyed by each day's local start-of-day. Days with no samples are omitted.
    func dailySteps(daysBack: Int) async throws -> [Date: Int] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(daysBack - 1), to: anchor) else {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        var interval = DateComponents()
        interval.day = 1

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: interval
        )

        let results = try await descriptor.result(for: store)

        var totals: [Date: Int] = [:]
        results.enumerateStatistics(from: start, to: Date()) { stats, _ in
            if let sum = stats.sumQuantity() {
                let day = calendar.startOfDay(for: stats.startDate)
                totals[day] = Int(sum.doubleValue(for: .count()))
            }
        }
        return totals
    }

    /// Plausible fake per-day step totals for previews and DEBUG testing
    /// (no Health access required). Covers the last `daysBack` days.
    static func sampleDailySteps(daysBack: Int = 42) -> [Date: Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var data: [Date: Int] = [:]
        for offset in 0..<daysBack {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            data[day] = Int.random(in: 0...14_000)
        }
        return data
    }

    private func sum(predicate: NSPredicate) async throws -> Int {
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum
        )
        let stats = try await descriptor.result(for: store)
        guard let sum = stats?.sumQuantity() else { return 0 }
        return Int(sum.doubleValue(for: .count()))
    }
}
