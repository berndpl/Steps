//
//  WatchContentView.swift
//  StepsWatch
//
//  The watch home mirrors the iOS home-screen widget: the shared `StepsMonthView`
//  renders the month grid plus today's step count (in the palette's goal color)
//  and today's activity badges — so colors, theme, and badges match everywhere.
//  Reads HealthKit directly on the watch and refreshes on activation. A small
//  toolbar button opens the places History, synced from the phone.
//

import SwiftUI
import WidgetKit

struct WatchContentView: View {
    @State private var dailySteps: [Date: Int]
    @State private var activities: Set<DayActivity>
    @State private var styleVersion = 0
    @State private var path = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase

    /// Default initializer: starts empty and fills from HealthKit on appear.
    /// The seeded parameters let SwiftUI previews render a populated grid without
    /// a live HealthKit read (which doesn't run in the canvas).
    init(previewSteps: [Date: Int] = [:], previewActivities: Set<DayActivity> = []) {
        _dailySteps = State(initialValue: previewSteps)
        _activities = State(initialValue: previewActivities)
    }

    var body: some View {
        NavigationStack(path: $path) {
            // Main view reserved for the grid + count + badges — the iOS widget layout.
            StepsMonthView(dailySteps: dailySteps, activities: activities)
                .id(styleVersion)   // rebuild with the new GridStyle when theme syncs in
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Steps")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { _ in
                    WatchHistoryView()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            WatchHistoryView()
                        } label: {
                            Image(systemName: "map")
                        }
                        .accessibilityLabel("History")
                    }
                }
        }
        .task { await load() }
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("-STEPS_WATCH_HISTORY") { path.append("history") }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchSync.themeDidChange)) { _ in
            styleVersion += 1
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func load() async {
        #if DEBUG
        if CommandLine.arguments.contains("-STEPS_WATCH_DEMO")
            || ProcessInfo.processInfo.environment["STEPS_WATCH_DEMO"] != nil {
            return   // keep the seeded demo data for screenshots
        }
        #endif
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
