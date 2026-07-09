//
//  WatchSync.swift
//  Steps
//
//  The single WatchConnectivity bridge between the iOS app and the watch. It
//  carries two things the watch can't get on its own, both in one coalesced
//  `applicationContext` (WCSession keeps only one, so they travel together):
//
//    1. The grid **theme** (palette, curve, spread, shape, marker). The App Group
//       cache is per-device, so the phone — the source of truth — pushes the 6
//       grid keys and the watch mirrors them into its own SettingsStore so
//       `GridStyle.current` matches.
//    2. A compact **places digest** (home + recent places + the walk suggestion).
//       The visit history lives only in the phone's App Group (visit monitoring is
//       phone-only), so the watch has none — the phone ships a small, self-contained
//       snapshot the watch renders and turns into Maps walking directions. No
//       VisitLog / geocoding / routing runs on the watch.
//
//  Only one object may be a `WCSessionDelegate`, so this type owns both jobs.
//

import Foundation
import WatchConnectivity
#if os(iOS)
import CoreLocation
#endif

// MARK: - Places digest (shared value types)

/// One place shown in the watch history. `subtitle` is preformatted on the phone
/// ("2.4 km · ~3,300 steps round trip" / "Home base") so the watch just displays
/// it; the raw coordinate + name drive the Maps walking-directions launch.
struct WatchPlace: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var subtitle: String
    var isHome: Bool
}

/// The snapshot the phone pushes to the watch: recent places (newest first, home
/// flagged) plus the current round-trip suggestion, if any.
struct WatchPlacesDigest: Codable, Equatable {
    var generatedAt: Date
    /// Full suggestion sentence, or nil when there's no gap / nothing suitable.
    var suggestionText: String?
    /// Which `WatchPlace` the suggestion points at (for the Maps launch on tap).
    var suggestionPlaceID: UUID?
    var places: [WatchPlace]
}

final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    /// Posted on the watch after a fresh theme arrives, so views can refresh.
    static let themeDidChange = Notification.Name("WatchSync.themeDidChange")
    /// Posted on the watch after a fresh places digest arrives.
    static let placesDidChange = Notification.Name("WatchSync.placesDidChange")

    /// The latest places digest the watch received (nil until the first sync).
    static private(set) var latestDigest: WatchPlacesDigest?

    private static let placesKey = "placesDigest"

    private static let keys = [
        SettingsStore.gridRampHexKey, SettingsStore.gridGoalHexKey,
        SettingsStore.gridCurveKey, SettingsStore.gridSpreadKey,
        SettingsStore.gridShapeKey, SettingsStore.gridMarkerKey,
    ]

    #if os(iOS)
    /// The last digest we built, so a theme-only push (e.g. a slider drag) can
    /// re-send the places snapshot without rebuilding it.
    private var lastDigestData: Data?
    #endif

    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// The current grid-theme keys as a context dict.
    private func themeContext() -> [String: Any] {
        var ctx: [String: Any] = [:]
        for key in Self.keys where SettingsStore.defaults.object(forKey: key) != nil {
            ctx[key] = SettingsStore.defaults.object(forKey: key)
        }
        return ctx
    }

    #if os(iOS)
    /// Phone → watch: publish the current theme + the last known places digest.
    /// Cheap and synchronous — safe to call on every theme edit.
    func push() {
        guard WCSession.default.activationState == .activated else { return }
        var ctx = themeContext()
        if let data = lastDigestData { ctx[Self.placesKey] = data }
        guard !ctx.isEmpty else { return }
        try? WCSession.default.updateApplicationContext(ctx)
    }

    /// Rebuild the places digest from the visit log + today's suggestion, cache it,
    /// then push. Call when visits or the suggestion may have changed.
    func refreshPlaces() {
        Task {
            let digest = await Self.buildDigest()
            self.lastDigestData = try? JSONEncoder().encode(digest)
            self.push()
        }
    }

    /// Assemble a compact snapshot: recent places (home flagged, ~10 max) with a
    /// preformatted subtitle, plus the current round-trip suggestion. Round-trip
    /// costs come from the cache filled by `resolveRoundTrip` (no fresh network
    /// unless a value is missing).
    static func buildDigest() async -> WatchPlacesDigest {
        let clusters = VisitLog.clusters()
        let home = VisitDistance.homeCluster(from: clusters)
        let homeID = home?.id

        var places: [WatchPlace] = []
        for cluster in clusters.prefix(10) {
            let isHome = cluster.id == homeID
            let name = cluster.name ?? VisitDistance.coordinateLabel(cluster.coordinate)
            let subtitle = await subtitle(for: cluster, isHome: isHome, home: home)
            places.append(WatchPlace(id: cluster.id,
                                     name: name,
                                     latitude: cluster.coordinate.latitude,
                                     longitude: cluster.coordinate.longitude,
                                     subtitle: subtitle,
                                     isHome: isHome))
        }

        var suggestionText: String?
        var suggestionPlaceID: UUID?
        if let steps = try? await HealthKitService.shared.todaySteps(),
           let s = await VisitDistance.todaySuggestion(todaySteps: steps) {
            suggestionText = "A round trip to \(s.name) — about \(s.roundTripSteps.formatted()) steps — would get you there."
            if let match = places.first(where: { coordinatesMatch($0, s.destination) }) {
                suggestionPlaceID = match.id
            } else {
                // The suggested place fell outside the recent window — add it so the
                // watch can still launch Maps directions to it.
                let p = WatchPlace(id: UUID(),
                                   name: s.name,
                                   latitude: s.destination.latitude,
                                   longitude: s.destination.longitude,
                                   subtitle: "\(VisitDistance.distanceString(s.roundTripMeters)) · ~\(s.roundTripSteps.formatted()) steps round trip",
                                   isHome: false)
                places.insert(p, at: min(1, places.count))
                suggestionPlaceID = p.id
            }
        }

        return WatchPlacesDigest(generatedAt: Date(),
                                 suggestionText: suggestionText,
                                 suggestionPlaceID: suggestionPlaceID,
                                 places: places)
    }

    /// The row subtitle: "Home base", the cached round-trip cost, or a visit-count
    /// placeholder while the distance is still being measured.
    private static func subtitle(for cluster: VisitCluster, isHome: Bool, home: VisitCluster?) async -> String {
        if isHome { return "Home base" }
        if let home, let trip = await VisitDistance.resolveRoundTrip(for: cluster, home: home.coordinate) {
            return "\(VisitDistance.distanceString(trip.meters)) · ~\(trip.steps.formatted()) steps round trip"
        }
        return cluster.visitCount == 1 ? "1 visit" : "\(cluster.visitCount) visits"
    }

    private static func coordinatesMatch(_ place: WatchPlace, _ c: CLLocationCoordinate2D) -> Bool {
        abs(place.latitude - c.latitude) < 1e-6 && abs(place.longitude - c.longitude) < 1e-6
    }
    #endif

    /// Apply an incoming context: mirror the theme and, on the watch, decode the
    /// places digest.
    private func apply(_ context: [String: Any]) {
        for key in Self.keys where context[key] != nil {
            SettingsStore.defaults.set(context[key], forKey: key)
        }
        var placesChanged = false
        if let data = context[Self.placesKey] as? Data,
           let digest = try? JSONDecoder().decode(WatchPlacesDigest.self, from: data) {
            Self.latestDigest = digest
            placesChanged = true
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.themeDidChange, object: nil)
            if placesChanged {
                NotificationCenter.default.post(name: Self.placesDidChange, object: nil)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        // Phone side: as soon as the session is live, push the current theme + the
        // freshest places so a launching watch mirrors them without waiting.
        if state == .activated {
            push()
            refreshPlaces()
        }
        #else
        // Watch side: apply whatever the phone last published (theme + places).
        if let ctx = session.receivedApplicationContext as [String: Any]?, !ctx.isEmpty {
            apply(ctx)
        }
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    #if DEBUG
    /// Seed a deterministic places digest for screenshots / previews, bypassing
    /// the phone sync. Used by the watch `-STEPS_WATCH_DEMO 1` launch arg.
    static func seedDemoDigest() {
        // Match the project site's rose palette so watch captures are consistent.
        SettingsStore.defaults.set("#BE185D", forKey: SettingsStore.gridRampHexKey)
        SettingsStore.defaults.set("#F38BA8", forKey: SettingsStore.gridGoalHexKey)

        let park = WatchPlace(id: UUID(), name: "Riverside Park", latitude: 52.5170, longitude: 13.3889,
                              subtitle: "2.4 km · ~3,300 steps round trip", isHome: false)
        let cafe = WatchPlace(id: UUID(), name: "Café Nord", latitude: 52.5219, longitude: 13.4132,
                              subtitle: "1.1 km · ~1,500 steps round trip", isHome: false)
        let library = WatchPlace(id: UUID(), name: "City Library", latitude: 52.5133, longitude: 13.4001,
                                 subtitle: "3.0 km · ~4,100 steps round trip", isHome: false)
        let home = WatchPlace(id: UUID(), name: "Home", latitude: 52.5200, longitude: 13.4050,
                              subtitle: "Home base", isHome: true)
        latestDigest = WatchPlacesDigest(
            generatedAt: Date(),
            suggestionText: "A round trip to Riverside Park — about 3,300 steps — would get you there.",
            suggestionPlaceID: park.id,
            places: [home, park, cafe, library])
    }
    #endif
}
