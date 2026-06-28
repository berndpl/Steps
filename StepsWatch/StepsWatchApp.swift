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
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
