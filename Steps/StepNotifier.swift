//
//  StepNotifier.swift
//  Steps
//
//  Milestone notifications: an encouraging local notification at each crossed
//  1,000-step mark toward the daily goal. App-target only — scheduling happens in
//  the app process, driven by HealthKitService's step observer (so alerts ride the
//  same background wake-ups that refresh the widget).
//
//  Because background HealthKit delivery is throttled (~hourly when the app is
//  closed), several thousands can be crossed between wake-ups. We therefore send a
//  single "catch-up" notification for the *highest* newly-crossed milestone rather
//  than a burst of stale ones. A distinct message marks the 10k goal; nothing fires
//  above it, and the ladder resets each day (see SettingsStore.lastNotifiedThousand).
//

import Foundation
import UserNotifications

final class StepNotifier {
    static let shared = StepNotifier()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// Request alert + sound permission. Called when the user enables the toggle.
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Evaluate today's running total and post any due notifications: the highest
    /// newly-crossed 1,000-step milestone, and a special "new monthly best" alert
    /// when today first surpasses every other day this month. No-ops when the
    /// toggle is off. Safe to call on every step refresh.
    func evaluate(todaySteps: Int) {
        guard SettingsStore.notificationsEnabled else { return }
        evaluateMilestone(todaySteps: todaySteps)
        evaluateMonthlyRecord(todaySteps: todaySteps)
    }

    private func evaluateMilestone(todaySteps: Int) {
        let current = min(todaySteps / 1_000, 10)   // highest thousand reached, capped at goal
        let last = SettingsStore.lastNotifiedThousand
        guard current > last, current >= 1 else { return }

        SettingsStore.lastNotifiedThousand = current
        post(stage: stage(for: todaySteps), milestone: current)
    }

    /// Fire once, the moment today's total beats the best of every *other*
    /// current-month day. The prior best is computed from the shared cache
    /// (refreshed just before this runs), so it excludes today by construction.
    /// `priorBest > 0` avoids celebrating the first logged day of a month (no
    /// competition yet). A daily stamp prevents re-firing as today keeps climbing.
    private func evaluateMonthlyRecord(todaySteps: Int) {
        guard !SettingsStore.hasNotifiedMonthRecordToday else { return }

        let today = Calendar.current.startOfDay(for: Date())
        var monthData = SharedStore.load()
        monthData[today] = nil   // exclude today; compare against other days only
        guard let priorBest = monthBestDay(monthData)?.steps, priorBest > 0 else { return }
        guard todaySteps > priorBest else { return }

        SettingsStore.markMonthRecordNotifiedToday()
        postMonthlyRecord(steps: todaySteps)
    }

    private func post(stage: StepStage, milestone: Int) {
        let content = UNMutableNotificationContent()
        if milestone >= 10 {
            content.title = "\(stage.emoji) Goal reached!"
            content.body = stage.message
        } else {
            content.title = "\(stage.emoji) \( (milestone * 1_000).formatted() ) steps"
            content.body = stage.message
        }
        content.sound = .default

        // nil trigger → deliver immediately.
        let request = UNNotificationRequest(
            identifier: "milestone-\(milestone)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func postMonthlyRecord(steps: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🏅 New monthly best!"
        content.body = "\(steps.formatted()) steps — your biggest day this month."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "month-record-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
