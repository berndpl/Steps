//
//  StepsGridComplication.swift
//  StepsWidget
//
//  A compact GitHub-style step grid as an `.accessoryRectangular` complication —
//  shared by the iOS lock screen *and* the watchOS face. Accessory families are
//  rendered monochrome / vibrant-tinted by the system, which flattens the app's
//  OKLCH hue ramp. So instead of hue, this grid encodes each day's intensity via
//  cell **opacity** (which the tint preserves as brightness), keeping the
//  contribution-graph feel intact on a tinted face.
//
//  Layout is weeks-as-columns (7 weekday rows tall), which fits the wide, short
//  rectangular accessory far better than a tall calendar month would. Today's
//  activity reward badges (cycling / strength / mindful) trail the grid.
//

import WidgetKit
import SwiftUI

/// Richer entry than `StepsCountEntry`: the grid needs several weeks of history
/// plus today's activities for the reward badges.
struct GridAccessoryEntry: TimelineEntry {
    let date: Date
    let dailySteps: [Date: Int]
    var activities: Set<DayActivity> = []
}

/// Provider for the grid complication. Mirrors the home-screen grid provider's
/// freshness strategy (live read reconciled against the App Group cache) but is
/// shared verbatim by the watch bundle, where it reads the watch's own HealthKit.
struct GridAccessoryProvider: TimelineProvider {
    /// Weeks of history shown as columns. Six weeks (42 days) keeps cells legible
    /// in the narrow rectangular accessory while still reading as a month-ish grid.
    static let weeks = 6

    func placeholder(in context: Context) -> GridAccessoryEntry {
        GridAccessoryEntry(date: Date(), dailySteps: HealthKitService.sampleDailySteps(),
                           activities: [.cycling, .mindful])
    }

    func getSnapshot(in context: Context, completion: @escaping (GridAccessoryEntry) -> Void) {
        if context.isPreview {
            completion(GridAccessoryEntry(date: Date(), dailySteps: HealthKitService.sampleDailySteps(),
                                          activities: [.cycling, .mindful]))
            return
        }
        Task {
            completion(GridAccessoryEntry(date: Date(), dailySteps: await Self.currentSteps(),
                                          activities: await HealthKitService.shared.todayActivities()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GridAccessoryEntry>) -> Void) {
        Task {
            let entry = GridAccessoryEntry(date: Date(), dailySteps: await Self.currentSteps(),
                                           activities: await HealthKitService.shared.todayActivities())
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Freshest history: live HealthKit read reconciled with the App Group cache,
    /// since today's count only climbs and an extension read can lag the app.
    private static func currentSteps() async -> [Date: Int] {
        let cached = SharedStore.load()
        guard var data = try? await HealthKitService.shared.dailySteps(daysBack: weeks * 7),
              !data.isEmpty else {
            return cached
        }
        let today = Calendar.current.startOfDay(for: Date())
        data[today] = max(data[today] ?? 0, cached[today] ?? 0)
        return data
    }
}

/// Compact, opacity-encoded contribution grid for the rectangular accessory.
struct AccessoryGridView: View {
    let dailySteps: [Date: Int]
    var activities: Set<DayActivity> = []

    private let weeks = GridAccessoryProvider.weeks
    private let rows = 7   // weekday rows

    private var todaySteps: Int {
        dailySteps[Calendar.current.startOfDay(for: Date())] ?? 0
    }

    var body: some View {
        HStack(spacing: 6) {
            grid
            VStack(alignment: .trailing, spacing: 2) {
                Text(todaySteps, format: .number)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.6)
                ActivityBadges(activities: activities)
            }
        }
    }

    private var grid: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekdayToday = (cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7
        let currentWeekStart = cal.date(byAdding: .day, value: -weekdayToday, to: today) ?? today
        let firstWeekStart = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: currentWeekStart) ?? today

        return GeometryReader { geo in
            let spacing = max(geo.size.width * 0.02, 1)
            let cellW = (geo.size.width - spacing * CGFloat(weeks - 1)) / CGFloat(weeks)
            let cellH = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let cell = max(min(cellW, cellH), 1)
            let corner = cell * 0.25

            HStack(spacing: spacing) {
                ForEach(0..<weeks, id: \.self) { col in
                    VStack(spacing: spacing) {
                        ForEach(0..<rows, id: \.self) { row in
                            let date = cal.date(byAdding: .day, value: col * 7 + row, to: firstWeekStart) ?? today
                            cellView(date: date, today: today, corner: corner)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .aspectRatio(CGFloat(weeks) / CGFloat(rows), contentMode: .fit)
    }

    @ViewBuilder
    private func cellView(date: Date, today: Date, corner: CGFloat) -> some View {
        let steps = dailySteps[date] ?? 0
        // Opacity ramp survives the system's accessory tint where hue wouldn't.
        let level: Double = date > today
            ? 0.08
            : (steps == 0 ? 0.12 : 0.25 + 0.75 * min(Double(steps) / Double(dailyStepGoal), 1.0))

        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color.primary.opacity(level))
            .overlay {
                if date == today {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.primary, lineWidth: max(corner * 0.5, 1))
                }
            }
    }
}

struct StepsGridAccessoryWidget: Widget {
    let kind = "StepsGridAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GridAccessoryProvider()) { entry in
            AccessoryGridView(dailySteps: entry.dailySteps, activities: entry.activities)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(URL(string: "steps://open"))
        }
        .configurationDisplayName("Steps Grid")
        .description("Your recent weeks of steps as a compact contribution grid.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview("Steps Grid · Rectangular", as: .accessoryRectangular) {
    StepsGridAccessoryWidget()
} timeline: {
    GridAccessoryEntry(date: Date(), dailySteps: HealthKitService.sampleDailySteps(),
                       activities: [.cycling, .strength])
}
