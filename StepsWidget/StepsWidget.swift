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
            let data = (try? await HealthKitService.shared.dailySteps(daysBack: 35)) ?? [:]
            completion(StepsEntry(date: Date(), dailySteps: data))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        Task {
            let data = (try? await HealthKitService.shared.dailySteps(daysBack: 35)) ?? [:]
            let entry = StepsEntry(date: Date(), dailySteps: data)
            // Refresh roughly hourly; WidgetKit coalesces these.
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Plausible fake data for placeholder/preview (no Health access).
    static func sampleData() -> [Date: Int] {
        HealthKitService.sampleDailySteps()
    }
}

struct StepsWidgetEntryView: View {
    var entry: StepsEntry

    var body: some View {
        StepsGridView(dailySteps: entry.dailySteps)
            .padding(12)
    }
}

struct StepsWidget: Widget {
    let kind = "StepsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            StepsWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Steps Grid")
        .description("Your last month of steps as a GitHub-style grid.")
        .supportedFamilies([.systemSmall])
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
