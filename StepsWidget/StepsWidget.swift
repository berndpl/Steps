//
//  StepsWidget.swift
//  StepsWidget
//

import WidgetKit
import SwiftUI

struct StepsEntry: TimelineEntry {
    let date: Date
    let dailySteps: [Date: Int]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StepsEntry {
        StepsEntry(date: Date(), dailySteps: Self.sampleData())
    }

    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        if context.isPreview {
            completion(StepsEntry(date: Date(), dailySteps: Self.sampleData()))
            return
        }
        Task {
            completion(StepsEntry(date: Date(), dailySteps: await Self.currentSteps()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        Task {
            let entry = StepsEntry(date: Date(), dailySteps: await Self.currentSteps())
            // Fallback heartbeat so today's bucket keeps advancing even between
            // the app's observer-driven reloads. WidgetKit throttles/coalesces
            // these against the daily refresh budget, so 15 min is a request, not
            // a guarantee — the observer (see HealthKitService) is the primary,
            // change-driven path; this just bounds staleness when it can't run.
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Query HealthKit directly so the grid reflects the latest steps (the widget
    /// shares the app's Health authorization). Fall back to the App Group cache
    /// the app keeps in sync if a live read isn't available (e.g. before the
    /// app's first run or a transient query failure).
    private static func currentSteps() async -> [Date: Int] {
        if let fresh = try? await HealthKitService.shared.dailySteps(daysBack: 42), !fresh.isEmpty {
            return fresh
        }
        return SharedStore.load()
    }

    /// Plausible fake data for placeholder/preview (no Health access).
    static func sampleData() -> [Date: Int] {
        HealthKitService.sampleDailySteps()
    }
}

// MARK: - Accessory (lock-screen) widgets

/// Lightweight entry for the accessory widgets — they only need today's running
/// total, not the whole month of history the grid uses.
struct StepsCountEntry: TimelineEntry {
    let date: Date
    let steps: Int
}

/// Shared provider for both accessory widgets (Steps Ring, Tiny Steps). Mirrors
/// `Provider`'s freshness strategy and 15-minute heartbeat, but resolves to a
/// single Int — today's step total.
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

    /// Prefer a live HealthKit read (the widget shares the app's authorization);
    /// fall back to today's bucket in the App Group cache.
    private static func todaySteps() async -> Int {
        if let fresh = try? await HealthKitService.shared.todaySteps() {
            return fresh
        }
        let today = Calendar.current.startOfDay(for: Date())
        return SharedStore.load()[today] ?? 0
    }
}

struct StepsRingWidget: Widget {
    let kind = "StepsRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            StepsRingView(steps: entry.steps)
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
                .widgetURL(URL(string: "steps://open"))
        }
        .configurationDisplayName("Tiny Steps")
        .description("A little symbol that grows every 1,000 steps toward your goal.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Home-screen grid widget

struct StepsWidgetEntryView: View {
    var entry: StepsEntry

    var body: some View {
        ZStack {
            // Letters/Spark widget: a near-transparent backdrop, not a solid fill.
            Color.black.opacity(0.02)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.02)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            StepsMonthView(dailySteps: entry.dailySteps)
                .padding(18)   // Letters/Spark LayoutMetrics inset
        }
        .clipShape(ContainerRelativeShape())
    }
}

struct StepsWidget: Widget {
    let kind = "StepsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            StepsWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "steps://open"))
        }
        .configurationDisplayName("Steps Grid")
        .description("Your last month of steps as a GitHub-style grid.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct StepsWidgetBundle: WidgetBundle {
    var body: some Widget {
        StepsWidget()
        StepsRingWidget()
        TinyStepsWidget()
    }
}

#Preview(as: .systemSmall) {
    StepsWidget()
} timeline: {
    StepsEntry(date: Date(), dailySteps: Provider.sampleData())
}

#Preview("Ring", as: .accessoryCircular) {
    StepsRingWidget()
} timeline: {
    StepsCountEntry(date: Date(), steps: 6_240)
}

#Preview("Tiny", as: .accessoryCircular) {
    TinyStepsWidget()
} timeline: {
    StepsCountEntry(date: Date(), steps: 6_240)
}
