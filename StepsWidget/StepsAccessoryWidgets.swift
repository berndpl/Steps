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
}

/// Shared provider for both accessory widgets. Mirrors the grid provider's
/// freshness strategy and 15-minute heartbeat, but resolves to a single Int —
/// today's step total. On watchOS this reads the watch's own HealthKit store.
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepsCountEntry {
        StepsCountEntry(date: Date(), steps: 6_240)
    }

    func getSnapshot(in context: Context, completion: @escaping (StepsCountEntry) -> Void) {
        if context.isPreview {
            completion(StepsCountEntry(date: Date(), steps: 6_240))
            return
        }
        Task {
            completion(StepsCountEntry(date: Date(), steps: await Self.todaySteps()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsCountEntry>) -> Void) {
        Task {
            let entry = StepsCountEntry(date: Date(), steps: await Self.todaySteps())
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
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            StepsRingView(steps: entry.steps)
                // Every widget must declare a container background, or accessory
                // families render broken on the lock screen / watch face.
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(URL(string: "steps://open"))
        }
        .configurationDisplayName("Steps Ring")
        .description("Today's steps with a ring toward your daily goal.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TinyStepsWidget: Widget {
    let kind = "TinyStepsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TinyStepsView(steps: entry.steps)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(URL(string: "steps://open"))
        }
        .configurationDisplayName("Tiny Steps")
        .description("A little symbol that grows every 1,000 steps toward your goal.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
