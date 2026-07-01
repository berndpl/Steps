//
//  WatchContentView.swift
//  StepsWatch
//
//  The familiar month grid — same as the iOS home-screen widget — rendered with
//  the shared StepsMonthView so colors, theme, and badges match. Reads HealthKit
//  on the watch and refreshes on activation.
//

import SwiftUI
import WidgetKit

struct WatchContentView: View {
    @State private var dailySteps: [Date: Int]
    @State private var activities: Set<DayActivity>
    @State private var styleVersion = 0
    @Environment(\.scenePhase) private var scenePhase

    /// Default initializer: starts empty and fills from HealthKit on appear.
    /// The seeded parameters let SwiftUI previews render a populated grid without
    /// a live HealthKit read (which doesn't run in the canvas).
    init(previewSteps: [Date: Int] = [:], previewActivities: Set<DayActivity> = []) {
        _dailySteps = State(initialValue: previewSteps)
        _activities = State(initialValue: previewActivities)
    }

    var body: some View {
        StepsGridView(dailySteps: dailySteps)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .id(styleVersion)   // rebuild with the new GridStyle when theme syncs in
            .task { await load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await load() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: ThemeSync.themeDidChange)) { _ in
                styleVersion += 1
                WidgetCenter.shared.reloadAllTimelines()
            }
    }

    private func load() async {
        try? await HealthKitService.shared.requestAuthorization()
        if let data = try? await HealthKitService.shared.dailySteps(daysBack: 42) {
            dailySteps = data
        }
        activities = await HealthKitService.shared.todayActivities()
    }
}

#Preview {
    WatchContentView(previewSteps: HealthKitService.sampleDailySteps(),
                     previewActivities: [.cycling, .strength])
}
