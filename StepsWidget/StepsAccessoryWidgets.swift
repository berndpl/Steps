//
//  StepsAccessoryWidgets.swift
//  StepsWidget
//
//  The accessory widgets (Steps Ring, Tiny Steps) and their provider, shared by
//  the iOS widget extension *and* the watchOS widget extension (complications).
//  The per-platform @main WidgetBundle decides which of these it exposes:
//  iOS adds them alongside the home-screen grid; watchOS exposes only these.
//

import WidgetKit
import SwiftUI

/// Lightweight entry for the accessory widgets — they only need today's running
/// total, not the whole month of history the grid uses.
struct StepsCountEntry: TimelineEntry {
    let date: Date
    let steps: Int
    /// Today's activities (cycling / strength / mindful), surfaced as small reward
    /// badges in the roomy `.accessoryRectangular` family. Ignored by the tight
    /// circular / corner / inline families, which have no room for them.
    var activities: Set<DayActivity> = []
}

/// Shared provider for both accessory widgets. Mirrors the grid provider's
/// freshness strategy and 15-minute heartbeat, but resolves to a single Int —
/// today's step total. On watchOS this reads the watch's own HealthKit store.
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepsCountEntry {
        StepsCountEntry(date: Date(), steps: 6_240, activities: [.cycling])
    }

    func getSnapshot(in context: Context, completion: @escaping (StepsCountEntry) -> Void) {
        if context.isPreview {
            completion(StepsCountEntry(date: Date(), steps: 6_240, activities: [.cycling]))
            return
        }
        Task {
            completion(StepsCountEntry(date: Date(), steps: await Self.todaySteps(),
                                       activities: await HealthKitService.shared.todayActivities()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsCountEntry>) -> Void) {
        Task {
            let entry = StepsCountEntry(date: Date(), steps: await Self.todaySteps(),
                                        activities: await HealthKitService.shared.todayActivities())
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Today's freshest step total. A HealthKit read from *inside the widget
    /// extension* can lag the main app (the extension's store isn't always
    /// synced), and that stale read still succeeds — so trusting it alone can show
    /// an older, lower count than the app does. Since steps only climb during a
    /// day, take the max of the App Group cache (which the app refreshes on every
    /// foreground + background step wake) and a live read.
    private static func todaySteps() async -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let cached = SharedStore.load()[today] ?? 0
        let live = (try? await HealthKitService.shared.todaySteps()) ?? 0
        return max(cached, live)
    }
}

struct StepsRingWidget: Widget {
    let kind = "StepsRingWidget"

    var body: some WidgetConfiguration {
        var families: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #if os(watchOS)
        families.append(.accessoryCorner)
        #endif
        return StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            StepsRingView(steps: entry.steps, activities: entry.activities)
                // Every widget must declare a container background, or accessory
                // families render broken on the lock screen / watch face.
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(URL(string: "steps://open"))
        }
        .configurationDisplayName("Steps Ring")
        .description("Today's steps with a ring toward your daily goal.")
        .supportedFamilies(families)
    }
}

struct TinyStepsWidget: Widget {
    let kind = "TinyStepsWidget"

    var body: some WidgetConfiguration {
        var families: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #if os(watchOS)
        families.append(.accessoryCorner)
        #endif
        return StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TinyStepsView(steps: entry.steps, activities: entry.activities)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(URL(string: "steps://open"))
        }
        .configurationDisplayName("Tiny Steps")
        .description("A little symbol that grows every 1,000 steps toward your goal.")
        .supportedFamilies(families)
    }
}
