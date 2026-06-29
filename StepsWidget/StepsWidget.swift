//
//  StepsWidget.swift
//  StepsWidget
//

import WidgetKit
import SwiftUI

struct StepsEntry: TimelineEntry {
    let date: Date
    let dailySteps: [Date: Int]
    var activities: Set<DayActivity> = []
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StepsEntry {
        StepsEntry(date: Date(), dailySteps: Self.sampleData(), activities: [.cycling, .mindful])
    }

    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        if context.isPreview {
            completion(StepsEntry(date: Date(), dailySteps: Self.sampleData(), activities: [.cycling, .mindful]))
            return
        }
        Task {
            completion(StepsEntry(date: Date(), dailySteps: await Self.currentSteps(),
                                  activities: await HealthKitService.shared.todayActivities()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        Task {
            let entry = StepsEntry(date: Date(), dailySteps: await Self.currentSteps(),
                                   activities: await HealthKitService.shared.todayActivities())
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
    /// the app keeps in sync if a live read isn't available. Reconcile *today*
    /// with the cache too: a widget-extension read can lag the main app, and since
    /// today's count only climbs, the higher of the two is the freshest.
    private static func currentSteps() async -> [Date: Int] {
        let cached = SharedStore.load()
        guard var data = try? await HealthKitService.shared.dailySteps(daysBack: 42),
              !data.isEmpty else {
            return cached
        }
        let today = Calendar.current.startOfDay(for: Date())
        data[today] = max(data[today] ?? 0, cached[today] ?? 0)
        return data
    }

    /// Plausible fake data for placeholder/preview (no Health access).
    static func sampleData() -> [Date: Int] {
        HealthKitService.sampleDailySteps()
    }
}

// MARK: - Home-screen grid widget

struct StepsWidgetEntryView: View {
    var entry: StepsEntry
    @Environment(\.widgetFamily) private var family

    private var todaySteps: Int {
        entry.dailySteps[Calendar.current.startOfDay(for: Date())] ?? 0
    }

    var body: some View {
        ZStack {
            // Letters/Spark widget: a near-transparent backdrop, not a solid fill.
            Color.black.opacity(0.02)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.02)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            switch family {
            case .systemMedium:
                HStack(spacing: 16) {
                    StepsGridView(dailySteps: entry.dailySteps)
                        .aspectRatio(1, contentMode: .fit)
                    statsPanel
                    Spacer(minLength: 0)
                }
                .padding(18)
            case .systemLarge:
                StepsMonthView(dailySteps: entry.dailySteps, activities: entry.activities)
                    .padding(20)
            default: // .systemSmall
                StepsMonthView(dailySteps: entry.dailySteps, activities: entry.activities)
                    .padding(18)
            }
        }
        .clipShape(ContainerRelativeShape())
    }

    /// Side panel for the medium family: today's count + stage glyph, activity
    /// badges, and the month's best day.
    private var statsPanel: some View {
        let stage = stage(for: todaySteps)
        let best = monthBestDay(entry.dailySteps)
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: stage.symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(GridStyle.current.goalColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(todaySteps, format: .number)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(GridStyle.current.goalColor)
                Text("of \(dailyStepGoal.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !entry.activities.isEmpty {
                HStack(spacing: 4) {
                    ForEach(DayActivity.allCases.filter(entry.activities.contains)) { activity in
                        Image(systemName: activity.symbol)
                            .font(.footnote)
                            .foregroundStyle(GridStyle.current.goalColor)
                    }
                }
            }
            Spacer(minLength: 0)
            if let best {
                Text("Best \(best.steps.formatted())")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct StepsWidgetBundle: WidgetBundle {
    var body: some Widget {
        StepsWidget()
        StepsRingWidget()
        TinyStepsWidget()
        StepsGridAccessoryWidget()
    }
}

#Preview(as: .systemSmall) {
    StepsWidget()
} timeline: {
    StepsEntry(date: Date(), dailySteps: Provider.sampleData())
}

#Preview(as: .systemMedium) {
    StepsWidget()
} timeline: {
    StepsEntry(date: Date(), dailySteps: Provider.sampleData(), activities: [.cycling, .strength])
}

#Preview(as: .systemLarge) {
    StepsWidget()
} timeline: {
    StepsEntry(date: Date(), dailySteps: Provider.sampleData(), activities: [.cycling, .mindful])
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
