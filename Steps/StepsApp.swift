//
//  StepsApp.swift
//  Steps
//
//  Created by Bernd on 24.06.26.
//

import SwiftUI

@main
struct StepsApp: App {
    // An app delegate so we also run on background relaunches that HealthKit
    // triggers (when no scene/UI is shown) — that's where the observer must be
    // re-registered to keep the widget current while the app is closed.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Drive milestone notifications from the step observer: every refresh
        // (foreground or background wake-up) passes today's total here, and the
        // notifier decides whether a new 1,000-step mark warrants an alert. Set
        // before observing so the first refresh is covered. `evaluate` itself
        // no-ops when the toggle is off.
        HealthKitService.onStepsUpdate = { todaySteps in
            StepNotifier.shared.evaluate(todaySteps: todaySteps)
        }
        // Begin observing step changes immediately so background wake-ups can
        // refresh the cache and reload the widget. No-ops until access is granted.
        HealthKitService.shared.startObservingSteps()
        return true
    }
}
