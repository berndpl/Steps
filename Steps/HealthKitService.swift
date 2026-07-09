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
import WidgetKit

/// Daily step goal used to bucket grid intensity. GitHub-style "usage" is
/// measured relative to this fixed goal so colors mean the same thing every day.
let dailyStepGoal = 10_000

/// Maps a day's step total to an intensity level 0...5.
///
/// Levels 1–4 are quarters of the 10k goal so the green ramp reads like GitHub's
/// contribution graph; level 5 is reserved for days that *reached the goal*, which
/// get a distinct standout color (not just the darkest green):
///   0 → 0 (empty), 1–2500 → 1, 2501–5000 → 2, 5001–7500 → 3,
///   7501–9999 → 4, 10000+ → 5 (goal reached).
func level(for steps: Int) -> Int {
    switch steps {
    case ..<1: return 0
    case ..<2_501: return 1
    case ..<5_001: return 2
    case ..<7_501: return 3
    case ..<dailyStepGoal: return 4
    default: return 5
    }
}

/// A "Tiny Steps" milestone: one stage per 1,000 steps, from a fresh start (0) to
/// the 10k goal (10). Each stage carries two faces of the same idea:
///   - `symbol`: an SF Symbol for widgets / lock screen / watch face, because those
///     surfaces render desaturated/tinted — symbols stay crisp where emoji would
///     flatten to a white blob.
///   - `emoji`: the colorful face for full-color notification banners.
/// Plus `message`, the encouraging line shown in the milestone notification.
///
/// The goal is fixed at 10,000 (see `dailyStepGoal`) so "every 1,000 steps = one
/// new symbol" maps cleanly to exactly these 11 stages.
struct StepStage {
    let thousands: Int   // 0...10
    let symbol: String   // SF Symbol name (tint-safe surfaces)
    let emoji: String    // notification banner (full color)
    let message: String  // encouraging copy
}

/// The 0…10 stage table. Index == thousands of steps completed.
private let stepStages: [StepStage] = [
    StepStage(thousands: 0,  symbol: "circle.dotted",      emoji: "🥚", message: "A fresh start — let's go."),
    StepStage(thousands: 1,  symbol: "figure.walk",        emoji: "🐣", message: "You're on your way!"),
    StepStage(thousands: 2,  symbol: "figure.walk",        emoji: "🐤", message: "Nice and steady."),
    StepStage(thousands: 3,  symbol: "figure.walk.motion", emoji: "🚶", message: "Finding your rhythm."),
    StepStage(thousands: 4,  symbol: "figure.walk.motion", emoji: "🚶", message: "Almost halfway there."),
    StepStage(thousands: 5,  symbol: "figure.run",         emoji: "🏃", message: "Halfway — keep it up!"),
    StepStage(thousands: 6,  symbol: "figure.run",         emoji: "🏃", message: "Past the midpoint!"),
    StepStage(thousands: 7,  symbol: "flame",              emoji: "🔥", message: "You're on fire."),
    StepStage(thousands: 8,  symbol: "flame.fill",         emoji: "🔥", message: "So close now."),
    StepStage(thousands: 9,  symbol: "bolt.fill",          emoji: "⚡️", message: "One more to the goal!"),
    StepStage(thousands: 10, symbol: "trophy.fill",        emoji: "🏆", message: "Goal reached! Amazing."),
]

/// The stage for a given step total. Clamped to the 10k goal — anything at or above
/// the goal is the final trophy stage.
func stage(for steps: Int) -> StepStage {
    let index = max(0, min(steps / 1_000, 10))
    return stepStages[index]
}

enum HealthKitError: Error {
    case notAvailable
    case noStepType
}

/// An activity done today, surfaced as a small badge on the widget. Each maps to
/// an SF Symbol; detection is from HealthKit workouts / mindful sessions.
enum DayActivity: String, CaseIterable, Identifiable {
    case cycling
    case mindful
    case strength

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cycling:  return "figure.outdoor.cycle.circle.fill"
        case .mindful:  return "figure.mind.and.body.circle.fill"
        case .strength: return "figure.strengthtraining.traditional.circle.fill"
        }
    }

    /// Human-readable name, shown when the user taps a badge.
    var label: String {
        switch self {
        case .cycling:  return "Cycling"
        case .mindful:  return "Mindful"
        case .strength: return "Strength"
        }
    }
}

/// Today's effort for a tracked activity — surfaced when the user taps its badge.
/// `minutes` comes from recorded workouts / mindful sessions; `distanceMeters`
/// (cycling only) is summed from `distanceCycling`, independent of any workout.
struct ActivityDetail: Equatable {
    var minutes: Int = 0
    var distanceMeters: Double = 0
}

/// Shared cache in the App Group container, written by the app and read by the
/// widget — so the widget renders instantly from synced data without needing its
/// own HealthKit query on every timeline refresh.
enum SharedStore {
    static let appGroup = "group.de.plontsch.steps"
    private static let key = "dailySteps"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Persist daily totals. Encoded as [startOfDay-epoch-string: steps] because
    /// UserDefaults can't store Date keys directly.
    static func save(_ steps: [Date: Int]) {
        let calendar = Calendar.current
        var encoded: [String: Int] = [:]
        for (date, count) in steps {
            let day = calendar.startOfDay(for: date)
            encoded[String(Int(day.timeIntervalSince1970))] = count
        }
        defaults?.set(encoded, forKey: key)
    }

    static func load() -> [Date: Int] {
        guard let encoded = defaults?.dictionary(forKey: key) as? [String: Int] else { return [:] }
        var out: [Date: Int] = [:]
        for (epoch, count) in encoded {
            if let t = TimeInterval(epoch) {
                out[Date(timeIntervalSince1970: t)] = count
            }
        }
        return out
    }
}

/// Small preferences + milestone-progress store in the same App Group container.
/// Kept beside `SharedStore` so the settings toggle and the milestone bookkeeping
/// are reachable from the app process (the only place notifications are scheduled).
enum SettingsStore {
    static let appGroup = SharedStore.appGroup

    /// Shared so `@AppStorage(..., store:)` in the UI and the background observer
    /// read/write the very same defaults. The watch has no App Group entitlement,
    /// so it uses `.standard` — a single reliable store that `WatchSync` writes the
    /// synced theme into and `GridStyle.current` reads back. iOS/widget use the
    /// App Group suite (falling back to `.standard` only if it's unavailable).
    #if os(watchOS)
    static let defaults = UserDefaults.standard
    #else
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard
    #endif

    /// Whether per-1,000-step milestone notifications are enabled.
    static let notificationsEnabledKey = "milestoneNotificationsEnabled"

    /// Whether the Health authorization sheet has been presented at least once.
    /// Persisted because HealthKit's read-access status is deliberately opaque,
    /// so this is the reliable signal for "we've already asked" (see
    /// `HealthKitService.needsAuthorizationPrompt`).
    private static let hasRequestedHealthAuthKey = "hasRequestedHealthAuth"
    static var hasRequestedHealthAuth: Bool {
        get { defaults.bool(forKey: hasRequestedHealthAuthKey) }
        set { defaults.set(newValue, forKey: hasRequestedHealthAuthKey) }
    }

    private static let lastNotifiedThousandKey = "lastNotifiedThousand"
    private static let lastNotifiedDayKey = "lastNotifiedDay"   // start-of-day epoch

    static var notificationsEnabled: Bool {
        defaults.bool(forKey: notificationsEnabledKey)
    }

    /// Highest thousand-milestone already notified *today*. Reading on a new day
    /// returns 0 so the next walk starts a fresh ladder of alerts.
    static var lastNotifiedThousand: Int {
        get {
            guard isToday(defaults.object(forKey: lastNotifiedDayKey) as? Double) else { return 0 }
            return defaults.integer(forKey: lastNotifiedThousandKey)
        }
        set {
            let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
            defaults.set(today, forKey: lastNotifiedDayKey)
            defaults.set(newValue, forKey: lastNotifiedThousandKey)
        }
    }

    // MARK: Monthly-record notification bookkeeping

    private static let monthRecordNotifiedDayKey = "monthRecordNotifiedDay"

    /// Whether the "new monthly best" alert already fired *today* — so it doesn't
    /// re-fire as today's total keeps climbing past the (unchanging) prior best.
    /// Resets daily; the record itself resets monthly because only current-month
    /// days are ever compared (see `monthBestDay`).
    static var hasNotifiedMonthRecordToday: Bool {
        isToday(defaults.object(forKey: monthRecordNotifiedDayKey) as? Double)
    }

    static func markMonthRecordNotifiedToday() {
        defaults.set(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970,
                     forKey: monthRecordNotifiedDayKey)
    }

    /// Generic "already fired this notification today" guard, keyed by a short
    /// name — used by the fun moments (streak, double-goal, record, morning) so
    /// each fires at most once per day and resets daily.
    static func hasFiredToday(_ key: String) -> Bool {
        isToday(defaults.object(forKey: "fired.\(key).day") as? Double)
    }
    static func markFiredToday(_ key: String) {
        defaults.set(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970,
                     forKey: "fired.\(key).day")
    }

    // MARK: Grid appearance (read by the widget via the App Group)

    // Keys are public so `@AppStorage(key, store: SettingsStore.defaults)` in the
    // customization sheet writes the very same values these accessors read.
    static let gridRampHexKey = "gridRampHex"
    static let gridGoalHexKey = "gridGoalHex"
    static let gridTodayHexKey = "gridTodayHex"
    static let gridCurveKey = "gridCurve"
    static let gridSpreadKey = "gridSpread"
    static let gridShapeKey = "gridShape"
    static let gridMarkerKey = "gridMarker"

    static var gridRampHex: String {
        defaults.string(forKey: gridRampHexKey) ?? GridStyle.defaultRampHex
    }
    static var gridGoalHex: String {
        defaults.string(forKey: gridGoalHexKey) ?? GridStyle.defaultGoalHex
    }
    static var gridTodayHex: String {
        defaults.string(forKey: gridTodayHexKey) ?? GridStyle.defaultTodayHex
    }
    static var gridCurve: String {
        defaults.string(forKey: gridCurveKey) ?? CurveShape.easeIn.rawValue
    }
    static var gridSpread: Double {
        (defaults.object(forKey: gridSpreadKey) as? Double) ?? GridStyle.defaultSpread
    }
    static var gridShape: String {
        defaults.string(forKey: gridShapeKey) ?? DayShape.roundedSquare.rawValue
    }
    static var gridMarker: String {
        defaults.string(forKey: gridMarkerKey) ?? BestDayMarker.dot.rawValue
    }

    // MARK: Flyover camera perspectives (start + end)

    /// The camera tilt (degrees; 0 = top-down, ~80 = near-horizon) and zoom
    /// (camera distance in meters) a route flyover holds constant for the whole
    /// walk. Persisted so every future flyover reuses the framing you dial in.
    /// Camera-only: this never changes the walk's start location or step math.
    private static let flyoverTiltKey = "flyoverTilt"
    private static let flyoverZoomKey = "flyoverZoom"
    private static let flyoverHeadingOffsetKey = "flyoverHeadingOffset"

    static let flyoverDefaultTilt: Double = 62
    static let flyoverDefaultZoom: Double = 280

    static var flyoverTilt: Double {
        get { defaults.object(forKey: flyoverTiltKey) as? Double ?? flyoverDefaultTilt }
        set { defaults.set(newValue, forKey: flyoverTiltKey) }
    }

    static var flyoverZoom: Double {
        get { defaults.object(forKey: flyoverZoomKey) as? Double ?? flyoverDefaultZoom }
        set { defaults.set(newValue, forKey: flyoverZoomKey) }
    }

    /// A heading offset (degrees) added to the route's own direction, so the user
    /// can rotate the flyover's viewing angle with a gesture and keep it.
    static var flyoverHeadingOffset: Double {
        get { defaults.object(forKey: flyoverHeadingOffsetKey) as? Double ?? 0 }
        set { defaults.set(newValue, forKey: flyoverHeadingOffsetKey) }
    }

    private static func isToday(_ epoch: Double?) -> Bool {
        guard let epoch else { return false }
        let stored = Date(timeIntervalSince1970: epoch)
        return Calendar.current.isDateInToday(stored)
    }
}

final class HealthKitService {
    static let shared = HealthKitService()

    /// Set by the app (in `AppDelegate`) to react to every step refresh — used to
    /// fire milestone notifications. Lives here so the same observer that updates
    /// the widget cache also drives alerts, on the same (throttled) background
    /// wake-ups. Receives today's running total.
    static var onStepsUpdate: ((Int) -> Void)?

    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private let cyclingDistanceType = HKQuantityType(.distanceCycling)

    /// Every Health type the app reads. Used for both the authorization request
    /// and the request-status check so they never drift apart.
    private var readTypes: Set<HKObjectType> {
        [stepType, cyclingDistanceType, HKObjectType.workoutType(), HKCategoryType(.mindfulSession)]
    }

    /// Retained so the long-lived observer query keeps running; also guards
    /// against registering it more than once per launch.
    private var observerQuery: HKObserverQuery?

    private init() {}

    /// Starts a long-lived observer that refreshes the shared cache and reloads
    /// the widget whenever HealthKit reports new step samples — so the grid keeps
    /// up with the current step count without the user opening the app.
    ///
    /// Paired with background delivery, iOS wakes the app (subject to its own
    /// throttling — roughly hourly for step count in the background) when new
    /// samples land; while the app is in the foreground the observer fires
    /// immediately. Safe to call repeatedly; it only registers once.
    ///
    /// Requires the `com.apple.developer.healthkit.background-delivery`
    /// entitlement and granted read access (no-ops harmlessly before either).
    func startObservingSteps() {
        guard HKHealthStore.isHealthDataAvailable(), observerQuery == nil else { return }

        store.enableBackgroundDelivery(for: stepType, frequency: .immediate) { _, _ in
            // Errors here (e.g. before authorization) are expected and ignored;
            // delivery starts working once access is granted on a later launch.
        }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, _ in
            Task {
                let data = await self?.refreshSharedCache() ?? [:]
                WidgetCenter.shared.reloadAllTimelines()
                // Drive milestone notifications from the same wake-up that refreshed
                // the widget cache (no separate background mechanism). Pass today's
                // running total; the app-side hook decides whether to alert.
                let today = Calendar.current.startOfDay(for: Date())
                Self.onStepsUpdate?(data[today] ?? 0)
                // Tell HealthKit we finished handling this (possibly background)
                // update, so it can release the app and schedule the next wake.
                completionHandler()
            }
        }
        store.execute(query)
        observerQuery = query
    }

    /// Requests read access to step count and workouts (for cycling minutes).
    /// Safe to call repeatedly; iOS only prompts the user the first time.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        // The sheet has now been presented (grant or deny). Record it so the UI
        // never traps on the permission screen — read-only status is ambiguous.
        SettingsStore.hasRequestedHealthAuth = true
    }

    /// Which tracked activities happened today (cycling/strength workouts, mindful
    /// sessions) — drives the widget badges. Empty on no access / nothing logged.
    func todayActivities() async -> Set<DayActivity> {
        let start = Calendar.current.startOfDay(for: Date())
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        var found: Set<DayActivity> = []

        // Workouts → cycling / strength.
        let workoutDescriptor = HKSampleQueryDescriptor(
            predicates: [.workout(datePredicate)], sortDescriptors: []
        )
        if let workouts = try? await workoutDescriptor.result(for: store) {
            for workout in workouts {
                switch workout.workoutActivityType {
                case .cycling:
                    found.insert(.cycling)
                case .traditionalStrengthTraining, .functionalStrengthTraining:
                    found.insert(.strength)
                default:
                    break
                }
            }
        }

        // Mindful sessions → meditation.
        let mindfulDescriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: datePredicate)],
            sortDescriptors: []
        )
        if let mindful = try? await mindfulDescriptor.result(for: store), !mindful.isEmpty {
            found.insert(.mindful)
        }

        // Cycling can also be inferred from distance — a casual ride that no app
        // recorded as a formal *workout* still logs `distanceCycling`. So award the
        // badge whenever any cycling distance exists today, independent of workouts.
        if !found.contains(.cycling), await todayCyclingDistanceMeters() > 0 {
            found.insert(.cycling)
        }

        return found
    }

    /// Per-activity time/distance for today, keyed by `DayActivity`. Drives the
    /// in-app tap-to-reveal badge detail. A key is present only when that activity
    /// happened today; cycling can appear via distance alone (no workout needed).
    func todayActivityDetails() async -> [DayActivity: ActivityDetail] {
        let start = Calendar.current.startOfDay(for: Date())
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        var details: [DayActivity: ActivityDetail] = [:]

        // Workouts → cycling / strength minutes.
        let workoutDescriptor = HKSampleQueryDescriptor(
            predicates: [.workout(datePredicate)], sortDescriptors: []
        )
        if let workouts = try? await workoutDescriptor.result(for: store) {
            for workout in workouts {
                let minutes = Int(workout.duration / 60)
                switch workout.workoutActivityType {
                case .cycling:
                    details[.cycling, default: ActivityDetail()].minutes += minutes
                case .traditionalStrengthTraining, .functionalStrengthTraining:
                    details[.strength, default: ActivityDetail()].minutes += minutes
                default:
                    break
                }
            }
        }

        // Cycling distance (independent of any recorded workout).
        let cyclingMeters = await todayCyclingDistanceMeters()
        if cyclingMeters > 0 {
            details[.cycling, default: ActivityDetail()].distanceMeters = cyclingMeters
        }

        // Mindful sessions → minutes (summed session durations).
        let mindfulDescriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: datePredicate)],
            sortDescriptors: []
        )
        if let mindful = try? await mindfulDescriptor.result(for: store), !mindful.isEmpty {
            let minutes = mindful.reduce(0) { $0 + Int($1.endDate.timeIntervalSince($1.startDate) / 60) }
            details[.mindful] = ActivityDetail(minutes: minutes, distanceMeters: 0)
        }

        return details
    }

    /// Total cycling distance logged today, in meters, summed across all
    /// `distanceCycling` samples — independent of whether a workout was recorded.
    /// Returns 0 on no access / no rides.
    func todayCyclingDistanceMeters() async -> Double {
        let start = Calendar.current.startOfDay(for: Date())
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: cyclingDistanceType, predicate: datePredicate),
            options: .cumulativeSum
        )
        guard let stats = try? await descriptor.result(for: store),
              let sum = stats.sumQuantity() else { return 0 }
        return sum.doubleValue(for: .meter())
    }

    /// Total minutes of cycling logged today, summed across cycling workouts
    /// (Apple Watch auto-detected rides, the Fitness app, or third-party apps).
    /// Casual biking with nothing recording a workout won't be counted. Returns
    /// 0 on no access / no rides.
    func todayCyclingMinutes() async -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let cyclingPredicate = HKQuery.predicateForWorkouts(with: .cycling)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, cyclingPredicate])

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: []
        )
        guard let workouts = try? await descriptor.result(for: store) else { return 0 }
        let seconds = workouts.reduce(0.0) { $0 + $1.duration }
        return Int(seconds / 60)
    }

    /// Whether the app should present the Health authorization sheet.
    ///
    /// HealthKit deliberately obscures whether *read* access was granted (to
    /// avoid leaking the absence of data), and `authorizationStatus(for:)` only
    /// reports *share/write* status — which stays ambiguous for our read-only
    /// request. So we can't reliably re-derive "already asked" from the status
    /// alone. Instead we persist a flag once the sheet has been presented: after
    /// that we never bounce back to the permission screen (we read data, or show
    /// the "no data" state), which is what fixes tapping *Allow* appearing to do
    /// nothing. On a genuinely fresh install the flag is false and the step type
    /// is `.notDetermined`, so the prompt still shows.
    var needsAuthorizationPrompt: Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if SettingsStore.hasRequestedHealthAuth { return false }
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

    /// Fetch recent daily totals and write them to the shared App Group cache so
    /// the widget can render from synced data. Returns the data for reuse.
    @discardableResult
    func refreshSharedCache(daysBack: Int = 42) async -> [Date: Int] {
        let data = (try? await dailySteps(daysBack: daysBack)) ?? [:]
        if !data.isEmpty { SharedStore.save(data) }
        return data
    }

    /// Plausible fake per-day step totals for previews and DEBUG testing
    /// (no Health access required). Covers the last `daysBack` days.
    static func sampleDailySteps(daysBack: Int = 42) -> [Date: Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var data: [Date: Int] = [:]
        // Deterministic, tuned sample so widget placeholders and screenshots are
        // reproducible and read well: today is a solid mid-goal day (matches the
        // in-app hero number), and the rest is a fixed, pleasant month — a handful
        // of goal days, many partials, a few rest days — instead of pure noise.
        var rng = SeededGenerator(seed: 0x5_7E95_C0DE)
        for offset in 0..<daysBack {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if offset == 0 {
                data[day] = 8_432
                continue
            }
            switch Int.random(in: 0..<100, using: &rng) {
            case 0..<16:  data[day] = Int.random(in: 0...1_500, using: &rng)       // rest day
            case 16..<72: data[day] = Int.random(in: 3_000...9_500, using: &rng)   // partial
            default:      data[day] = Int.random(in: 10_000...14_000, using: &rng) // goal+
            }
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

/// A tiny deterministic RNG (SplitMix64) so sample/preview step data is stable
/// across launches — reproducible widget placeholders and screenshots.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
