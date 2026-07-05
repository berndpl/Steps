//
//  VisitLog.swift
//  Steps
//
//  A persistent history of the places you dwell, captured from Core Location's
//  low-power visit monitoring (`CLVisit`). Each arrival/departure the system
//  reports is recorded here so the in-app History (see HistoryView) can show
//  where you stay and travel — and, from that, suggest a round trip that would
//  close today's gap to the step goal.
//
//  Stored as a JSON blob in the App Group (mirroring NotificationLog), so writes
//  made during background visit wake-ups survive and the same log is readable
//  wherever SettingsStore is. Newest first, capped to a recent window.
//

import Foundation
import CoreLocation

/// One recorded visit: where you were, and the window you were there. Coordinates
/// are stored as plain doubles so the struct is trivially `Codable`. `name` is a
/// lazily-filled reverse-geocoded label; `roundTripMeters`/`roundTripSteps` cache
/// the walking cost home↔here so we don't recompute (or re-hit the network) each
/// time a row or suggestion needs it.
struct Visit: Codable, Identifiable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    /// Arrival; `nil` when Core Location didn't know (uses `date` as a fallback).
    let arrival: Date?
    /// Departure; `nil` while the visit is still ongoing.
    let departure: Date?
    let horizontalAccuracy: Double
    /// When the visit was recorded (used for ordering + as a dwell fallback).
    let recordedAt: Date

    /// Cached reverse-geocoded place name (filled lazily; nil until resolved).
    var name: String?
    /// Cached round-trip walking distance home → here → home, in meters.
    var roundTripMeters: Double?
    /// Cached estimated steps for that round trip.
    var roundTripSteps: Int?

    init(id: UUID = UUID(),
         latitude: Double,
         longitude: Double,
         arrival: Date?,
         departure: Date?,
         horizontalAccuracy: Double,
         recordedAt: Date = Date(),
         name: String? = nil,
         roundTripMeters: Double? = nil,
         roundTripSteps: Int? = nil) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.arrival = arrival
        self.departure = departure
        self.horizontalAccuracy = horizontalAccuracy
        self.recordedAt = recordedAt
        self.name = name
        self.roundTripMeters = roundTripMeters
        self.roundTripSteps = roundTripSteps
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// How long this visit lasted. Falls back gracefully when either end is
    /// unknown (an ongoing or point-in-time visit contributes no dwell).
    var duration: TimeInterval {
        guard let arrival, let departure else { return 0 }
        return max(0, departure.timeIntervalSince(arrival))
    }

    /// Best-effort start instant for ordering and overnight-dwell math.
    var start: Date { arrival ?? recordedAt }
    /// Best-effort end instant.
    var end: Date { departure ?? recordedAt }
}

/// Append-only (capped) history of visits, persisted in the App Group. Newest
/// first. Proximity de-duplication is handled by the readers that group nearby
/// visits into a single place (see `clusters`).
enum VisitLog {
    private static let key = "visitLog"
    private static let maxEntries = 500

    /// Two visits within this distance are treated as the same place.
    static let clusterRadius: CLLocationDistance = 80

    private static var defaults: UserDefaults { SettingsStore.defaults }

    /// Record a visit. Called from `LocationService` on each `CLVisit` callback.
    static func record(_ visit: Visit) {
        var entries = all()
        entries.insert(visit, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save(entries)
    }

    /// The full history, newest first.
    static func all() -> [Visit] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Visit].self, from: data) else { return [] }
        return entries
    }

    /// Persist the given list (used by `record` and by cache-updates that fill in
    /// resolved names / distances on existing visits).
    static func save(_ entries: [Visit]) {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    /// Replace a single visit in place (e.g. after resolving its name or distance),
    /// matched by id. No-op if it's no longer in the log.
    static func update(_ visit: Visit) {
        var entries = all()
        guard let idx = entries.firstIndex(where: { $0.id == visit.id }) else { return }
        entries[idx] = visit
        save(entries)
    }

    /// Wipe the history.
    static func clear() {
        defaults.removeObject(forKey: key)
    }

    /// Group visits into distinct places by proximity. Returns one `VisitCluster`
    /// per place, ordered by most recent activity first. This is what the History
    /// list and home-detection operate on (raw visits are noisy — the same café
    /// generates many `CLVisit`s over time).
    static func clusters() -> [VisitCluster] {
        var clusters: [VisitCluster] = []
        for visit in all() {
            if let idx = clusters.firstIndex(where: {
                $0.representative.location.distance(from: visit.location) <= clusterRadius
            }) {
                clusters[idx].add(visit)
            } else {
                clusters.append(VisitCluster(first: visit))
            }
        }
        return clusters.sorted { $0.lastSeen > $1.lastSeen }
    }
}

/// A distinct place: all the recorded visits that fall within `clusterRadius` of
/// each other, plus derived totals (visit count, total dwell, overnight dwell).
struct VisitCluster: Identifiable {
    private(set) var visits: [Visit]

    init(first: Visit) { visits = [first] }

    var id: UUID { representative.id }

    /// The visit used as the cluster's anchor (its coordinate + cached fields).
    /// The most recent one, so a freshly-resolved name/distance surfaces.
    var representative: Visit {
        visits.max(by: { $0.recordedAt < $1.recordedAt }) ?? visits[0]
    }

    var coordinate: CLLocationCoordinate2D { representative.coordinate }
    var location: CLLocation { representative.location }
    var name: String? { visits.compactMap(\.name).first }
    var visitCount: Int { visits.count }
    var lastSeen: Date { visits.map(\.recordedAt).max() ?? representative.recordedAt }

    /// Total time spent across all visits to this place.
    var totalDwell: TimeInterval { visits.reduce(0) { $0 + $1.duration } }

    /// Dwell time that falls within night hours (22:00–06:00), summed across all
    /// visits. The place with the greatest overnight dwell is treated as home.
    var overnightDwell: TimeInterval {
        visits.reduce(0) { $0 + Self.overnightOverlap(from: $1.start, to: $1.end) }
    }

    mutating func add(_ visit: Visit) { visits.append(visit) }

    /// Seconds of the interval [start, end] that lie within any 22:00–06:00 window.
    /// Walks night-by-night so multi-day visits are handled correctly.
    static func overnightOverlap(from start: Date, to end: Date) -> TimeInterval {
        guard end > start else { return 0 }
        let cal = Calendar.current
        var total: TimeInterval = 0
        // Start the scan from the evening of the day the visit began.
        var dayCursor = cal.startOfDay(for: start)
        let scanEnd = end
        while dayCursor <= scanEnd {
            // Night window: 22:00 this day → 06:00 next day.
            guard let nightStart = cal.date(bySettingHour: 22, minute: 0, second: 0, of: dayCursor),
                  let nextDay = cal.date(byAdding: .day, value: 1, to: dayCursor),
                  let nightEnd = cal.date(bySettingHour: 6, minute: 0, second: 0, of: nextDay) else {
                break
            }
            let overlapStart = max(start, nightStart)
            let overlapEnd = min(end, nightEnd)
            if overlapEnd > overlapStart { total += overlapEnd.timeIntervalSince(overlapStart) }
            dayCursor = nextDay
        }
        return total
    }
}
