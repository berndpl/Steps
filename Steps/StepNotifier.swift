//
//  StepNotifier.swift
//  Steps
//
//  Local notifications, scheduled in the app process and driven by
//  HealthKitService's step observer (so they ride the same background wake-ups
//  that refresh the widget). Background HealthKit delivery is throttled (~hourly
//  when closed), so everything here is "catch-up" friendly: per-day guards make
//  each alert fire at most once a day, and reset daily.
//
//  Beyond the per-1,000 milestone ladder and the goal alert, a few "fun moments"
//  celebrate notable days: a morning greeting, double-goal, goal streaks, and a
//  new record (best day in the cached ~6-week window). One evening "final push"
//  nudge fires after 18:00 when the goal is within reach (< 1,000 steps away).
//  All share one custom chime.
//
//  See DESIGN.md ("Notifications") for the full catalog of states, triggers,
//  per-day guards, and precedence.
//

import Foundation
import UserNotifications

final class StepNotifier {
    static let shared = StepNotifier()

    private let center = UNUserNotificationCenter.current()

    /// Custom in-app chime (bundled WAV) used for every Steps notification.
    private let chime = UNNotificationSound(named: UNNotificationSoundName("StepsChime.wav"))

    private init() {}

    /// Request alert + sound permission. Called when the user enables the toggle.
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Evaluate today's running total and post any due notifications. No-ops when
    /// the toggle is off. Safe to call on every step refresh.
    func evaluate(todaySteps: Int) {
        guard SettingsStore.notificationsEnabled else { return }
        evaluateMorning(todaySteps: todaySteps)
        evaluateMilestone(todaySteps: todaySteps)
        evaluateFinalPush(todaySteps: todaySteps)
        evaluateDoubleGoal(todaySteps: todaySteps)
        evaluateStreak(todaySteps: todaySteps)
        evaluateRecord(todaySteps: todaySteps)
    }

    // MARK: - Milestones (the per-1,000 ladder + goal)

    private func evaluateMilestone(todaySteps: Int) {
        let current = min(todaySteps / 1_000, 10)   // highest thousand reached, capped at goal
        let last = SettingsStore.lastNotifiedThousand
        guard current > last, current >= 1 else { return }

        SettingsStore.lastNotifiedThousand = current
        let s = stage(for: todaySteps)
        if current >= 10 {
            post(title: "\(s.emoji) Goal reached!", body: s.message, id: "goal")
        } else {
            post(title: "\(s.emoji) \((current * 1_000).formatted()) steps", body: s.message,
                 id: "milestone-\(current)")
        }
    }

    // MARK: - Fun moments (each at most once/day)

    /// Evening "final push": after 18:00, when the goal is close but not yet hit
    /// (within 1,000 steps), a single 🤏 "you're *this* close" nudge. The pinch
    /// frames the tiny gap left so the last lap feels achievable before the day
    /// runs out. Fires at most once/day and only below the goal, so it never
    /// competes with the goal-reached alert.
    private func evaluateFinalPush(todaySteps: Int) {
        let remaining = dailyStepGoal - todaySteps
        guard Calendar.current.component(.hour, from: Date()) >= 18,
              remaining > 0, remaining < 1_000,
              !SettingsStore.hasFiredToday("finalPush") else { return }
        SettingsStore.markFiredToday("finalPush")
        post(title: "🤏 So close!",
             body: "Just \(remaining.formatted()) steps to your \(dailyStepGoal.formatted())-step goal — you're this close.",
             id: "finalPush")
    }

    /// A cheerful greeting the first time today's steps land — but only in the
    /// morning, so an afternoon first-sync doesn't say "good morning" at 4pm.
    private func evaluateMorning(todaySteps: Int) {
        guard todaySteps > 0,
              Calendar.current.component(.hour, from: Date()) < 12,
              !SettingsStore.hasFiredToday("morning") else { return }
        SettingsStore.markFiredToday("morning")
        post(title: "🌅 First steps", body: "Good morning — you're moving!", id: "morning")
    }

    /// Twice the daily goal in a single day.
    private func evaluateDoubleGoal(todaySteps: Int) {
        guard todaySteps >= dailyStepGoal * 2, !SettingsStore.hasFiredToday("doubleGoal") else { return }
        SettingsStore.markFiredToday("doubleGoal")
        post(title: "💪 Double goal!", body: "\(todaySteps.formatted()) steps — twice your goal today.",
             id: "doubleGoal")
    }

    /// Consecutive days hitting the goal, celebrated at streak milestones.
    private func evaluateStreak(todaySteps: Int) {
        guard todaySteps >= dailyStepGoal, !SettingsStore.hasFiredToday("streak") else { return }
        let streak = goalStreakIncludingToday()
        guard [3, 7, 14, 30].contains(streak) else { return }
        SettingsStore.markFiredToday("streak")
        post(title: "🔥 \(streak)-day streak!",
             body: "\(streak) days at goal in a row. Keep it going!", id: "streak")
    }

    /// Today beats the best day in the cached window — a bigger deal than the
    /// monthly best, so it takes precedence and suppresses the monthly alert.
    private func evaluateRecord(todaySteps: Int) {
        let today = Calendar.current.startOfDay(for: Date())
        var data = SharedStore.load()
        data[today] = nil   // compare against other days only

        if !SettingsStore.hasFiredToday("record"),
           let best = data.values.max(), best > 0, todaySteps > best {
            SettingsStore.markFiredToday("record")
            SettingsStore.markMonthRecordNotifiedToday()   // suppress the lesser monthly alert
            post(title: "🏆 Record day!",
                 body: "\(todaySteps.formatted()) steps — your best in weeks!", id: "record")
            return
        }
        evaluateMonthlyRecord(todaySteps: todaySteps)
    }

    /// Fire once when today first beats the best of every *other* current-month
    /// day. Prior best comes from the cache (refreshed just before this runs), so
    /// it excludes today by construction. `> 0` skips the first logged day.
    private func evaluateMonthlyRecord(todaySteps: Int) {
        guard !SettingsStore.hasNotifiedMonthRecordToday else { return }
        let today = Calendar.current.startOfDay(for: Date())
        var monthData = SharedStore.load()
        monthData[today] = nil
        guard let priorBest = monthBestDay(monthData)?.steps, priorBest > 0,
              todaySteps > priorBest else { return }
        SettingsStore.markMonthRecordNotifiedToday()
        post(title: "🏅 New monthly best!",
             body: "\(todaySteps.formatted()) steps — your biggest day this month.", id: "month-record")
    }

    /// Streak length ending today (which the caller guaranteed hit the goal),
    /// walking backwards through the cached daily totals.
    private func goalStreakIncludingToday() -> Int {
        let cal = Calendar.current
        let data = SharedStore.load()
        var streak = 1
        var day = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date()
        while (data[cal.startOfDay(for: day)] ?? 0) >= dailyStepGoal {
            streak += 1
            guard streak <= 400, let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    // MARK: - Posting

    private func post(title: String, body: String, id: String) {
        // Mirror every posted alert into the in-app Inbox history (see InboxView),
        // so the user has a running log even for background-fired notifications.
        NotificationLog.record(title: title, body: body)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = chime
        let request = UNNotificationRequest(
            identifier: "\(id)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil   // deliver immediately
        )
        center.add(request)
    }
}
