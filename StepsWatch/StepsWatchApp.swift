//
//  StepsWatchApp.swift
//  StepsWatch
//
//  Minimal watchOS app whose main job is to host the step complications and
//  request HealthKit access on the watch (the watch has its own HealthKit store
//  and authorization — the App Group cache does not sync across devices, so the
//  watch reads Health directly).
//

import SwiftUI

@main
struct StepsWatchApp: App {
    private let demoMode = CommandLine.arguments.contains("-STEPS_WATCH_DEMO")
        || ProcessInfo.processInfo.arguments.contains("STEPS_WATCH_DEMO")

    init() {
        WatchSync.shared.activate()
        #if DEBUG
        if CommandLine.arguments.contains("-STEPS_WATCH_DEMO")
            || ProcessInfo.processInfo.environment["STEPS_WATCH_DEMO"] != nil {
            WatchSync.seedDemoDigest()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if demoMode || ProcessInfo.processInfo.environment["STEPS_WATCH_DEMO"] != nil {
                WatchContentView(previewSteps: HealthKitService.sampleDailySteps(),
                                 previewActivities: [.cycling, .strength])
            } else {
                WatchContentView()
            }
            #else
            WatchContentView()
            #endif
        }
    }
}
