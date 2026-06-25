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
            // Refresh roughly hourly; WidgetKit coalesces these.
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Prefer the App Group cache the app keeps in sync; fall back to a direct
    /// HealthKit query when the cache is empty (e.g. before the app's first run).
    private static func currentSteps() async -> [Date: Int] {
        let cached = SharedStore.load()
        if !cached.isEmpty { return cached }
        return (try? await HealthKitService.shared.dailySteps(daysBack: 42)) ?? [:]
    }

    /// Plausible fake data for placeholder/preview (no Health access).
    static func sampleData() -> [Date: Int] {
        HealthKitService.sampleDailySteps()
    }
}

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
    }
}

#Preview(as: .systemSmall) {
    StepsWidget()
} timeline: {
    StepsEntry(date: Date(), dailySteps: Provider.sampleData())
}
