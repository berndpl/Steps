//
//  ThemeSync.swift
//  Steps
//
//  Keeps the grid theme (palette, curve, spread, shape, marker) in sync between
//  the iOS app and the watch. The App Group cache is per-device, so it can't carry
//  the theme across — WatchConnectivity bridges it. The phone is the source of
//  truth: it pushes the 6 grid keys via `updateApplicationContext`, and the watch
//  writes them into its own SettingsStore so `GridStyle.current` matches.
//

import Foundation
import WatchConnectivity

final class ThemeSync: NSObject, WCSessionDelegate {
    static let shared = ThemeSync()

    /// Posted on the watch after a fresh theme arrives, so views can refresh.
    static let themeDidChange = Notification.Name("ThemeSync.themeDidChange")

    private static let keys = [
        SettingsStore.gridRampHexKey, SettingsStore.gridGoalHexKey,
        SettingsStore.gridCurveKey, SettingsStore.gridSpreadKey,
        SettingsStore.gridShapeKey, SettingsStore.gridMarkerKey,
    ]

    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// Phone → watch: publish the current grid theme so the watch can mirror it.
    func push() {
        guard WCSession.default.activationState == .activated else { return }
        var ctx: [String: Any] = [:]
        for key in Self.keys where SettingsStore.defaults.object(forKey: key) != nil {
            ctx[key] = SettingsStore.defaults.object(forKey: key)
        }
        guard !ctx.isEmpty else { return }
        try? WCSession.default.updateApplicationContext(ctx)
    }

    private func apply(_ context: [String: Any]) {
        for key in Self.keys where context[key] != nil {
            SettingsStore.defaults.set(context[key], forKey: key)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.themeDidChange, object: nil)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        // Phone side: as soon as the session is live, push the current theme so a
        // freshly launched watch mirrors it without waiting for a customization edit.
        if state == .activated { push() }
        #else
        // Watch side: apply whatever theme the phone last published.
        if let ctx = session.receivedApplicationContext as [String: Any]?, !ctx.isEmpty {
            apply(ctx)
        }
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
