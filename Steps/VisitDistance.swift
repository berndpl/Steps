//
//  VisitDistance.swift
//  Steps
//
//  The math that turns a log of places into something useful: which place is
//  home, how far it is to walk there and back, roughly how many steps that costs,
//  and — for the Today view — which round trip would close today's step gap.
//
//  Walking distance comes from MapKit (`MKDirections`), so it reflects real
//  routes rather than crow-flies. A straight-line fallback (×2) keeps rows and
//  suggestions populated when a route can't be found or the network is down.
//  Reverse-geocoding (`CLGeocoder`) gives places readable names. Both reach the
//  network — a deliberate trade for accuracy (see README).
//

import Foundation
import CoreLocation
import MapKit

enum VisitDistance {
    /// Average walking stride, in meters. Used to estimate steps from a distance
    /// (HealthKit can't attribute steps to a hypothetical route). ~0.72 m is a
    /// common adult average; refine later if we learn the user's real stride.
    static let strideMeters: Double = 0.72

    // MARK: - Home detection

    /// The home place: the cluster with the greatest accumulated overnight dwell
    /// (time spent there between 22:00 and 06:00). `nil` until we have any visits.
    static func homeCluster(from clusters: [VisitCluster]) -> VisitCluster? {
        let withNight = clusters.filter { $0.overnightDwell > 0 }
        if let best = withNight.max(by: { $0.overnightDwell < $1.overnightDwell }) {
            return best
        }
        // No overnight data yet — fall back to the most-dwelt place so "home"
        // still has a sensible value early on.
        return clusters.max(by: { $0.totalDwell < $1.totalDwell })
    }

    // MARK: - Steps estimate

    /// Estimated steps to cover a distance, given the average stride.
    static func steps(forMeters meters: Double) -> Int {
        guard meters > 0 else { return 0 }
        return Int((meters / strideMeters).rounded())
    }

    // MARK: - Round-trip walking distance

    /// Round-trip walking distance home → destination → home, in meters. Tries
    /// MapKit walking directions; falls back to straight-line × 2 if no route is
    /// available. Returns `nil` only when the two points are effectively the same.
    static func roundTripMeters(from home: CLLocationCoordinate2D,
                                to destination: CLLocationCoordinate2D) async -> Double? {
        let straightLine = CLLocation(latitude: home.latitude, longitude: home.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
        // Same place (or within cluster radius) — no meaningful trip.
        guard straightLine > VisitLog.clusterRadius else { return nil }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: home))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            if let route = response.routes.min(by: { $0.distance < $1.distance }) {
                return route.distance * 2   // there and back
            }
        } catch {
            // Fall through to the straight-line estimate.
        }
        return straightLine * 2
    }

    /// Compute and cache the round-trip distance + step estimate for a cluster,
    /// writing the values back onto its representative visit in the log so we
    /// don't recompute (or re-hit the network) next time.
    @discardableResult
    static func resolveRoundTrip(for cluster: VisitCluster,
                                 home: CLLocationCoordinate2D) async -> (meters: Double, steps: Int)? {
        // Use the cached value if we already have one.
        if let meters = cluster.representative.roundTripMeters,
           let steps = cluster.representative.roundTripSteps {
            return (meters, steps)
        }
        guard let meters = await roundTripMeters(from: home, to: cluster.coordinate) else { return nil }
        let est = steps(forMeters: meters)
        var visit = cluster.representative
        visit.roundTripMeters = meters
        visit.roundTripSteps = est
        VisitLog.update(visit)
        return (meters, est)
    }

    // MARK: - Reverse geocoding

    /// How far around a visit to look for a named venue. Kept close to the
    /// clustering radius so we snap to the place you actually dwelled at rather
    /// than a POI on the next block.
    static let poiSearchRadius: CLLocationDistance = 100

    /// Resolve a readable place name for a visit and cache it back into the log.
    /// Prefers a nearby point of interest (supermarket, playground, pool, café…)
    /// so a dwell reads as the venue you were at, not the street it's on. Falls
    /// back to a reverse-geocoded street/locality when no venue is close enough.
    /// Best-effort: leaves the name nil (callers show coordinates) on failure.
    static func resolveName(for visit: Visit) async {
        // Skip if already named.
        if let existing = VisitLog.all().first(where: { $0.id == visit.id }), existing.name != nil { return }

        var label = await nearbyPOIName(for: visit.coordinate)
        if label == nil {
            label = await reverseGeocodedLabel(for: visit.location)
        }
        guard let label else { return }
        var updated = visit
        updated.name = label
        VisitLog.update(updated)
    }

    /// The nearest named point of interest to the coordinate, within
    /// `poiSearchRadius`. Uses MapKit's POI search so venues (shops, parks,
    /// playgrounds, pools…) win over plain addresses. `nil` if nothing is close.
    private static func nearbyPOIName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: poiSearchRadius)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else { return nil }

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = response.mapItems
            .compactMap { item -> (name: String, distance: CLLocationDistance)? in
                guard let name = item.name else { return nil }
                let c = item.placemark.coordinate
                let distance = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: origin)
                return (name, distance)
            }
            .filter { $0.distance <= poiSearchRadius }
            .min { $0.distance < $1.distance }
        return nearest?.name
    }

    /// Street/locality fallback via reverse geocoding.
    private static func reverseGeocodedLabel(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
              let placemark = placemarks.first else { return nil }
        return placemark.name
            ?? placemark.thoroughfare
            ?? placemark.locality
            ?? placemark.subLocality
    }

    // MARK: - Today suggestion

    /// A round-trip suggestion for the Today view: the known non-home place whose
    /// estimated round-trip steps best fills the gap to the goal (preferring trips
    /// that reach or exceed it, then the closest under). `nil` when there's no gap
    /// or nothing suitable is known yet.
    struct Suggestion: Equatable {
        let name: String
        let roundTripMeters: Double
        let roundTripSteps: Int
    }

    static func todaySuggestion(todaySteps: Int) async -> Suggestion? {
        let gap = dailyStepGoal - todaySteps
        guard gap > 0 else { return nil }

        let clusters = VisitLog.clusters()
        guard let home = homeCluster(from: clusters) else { return nil }

        var candidates: [Suggestion] = []
        for cluster in clusters where cluster.id != home.id {
            guard let trip = await resolveRoundTrip(for: cluster, home: home.coordinate) else { continue }
            let label = cluster.name ?? coordinateLabel(cluster.coordinate)
            candidates.append(Suggestion(name: label, roundTripMeters: trip.meters, roundTripSteps: trip.steps))
        }
        guard !candidates.isEmpty else { return nil }

        // Prefer the smallest trip that still reaches the goal; if none reaches it,
        // pick the largest available (gets you closest).
        let reaching = candidates.filter { $0.roundTripSteps >= gap }
        if let best = reaching.min(by: { $0.roundTripSteps < $1.roundTripSteps }) { return best }
        return candidates.max(by: { $0.roundTripSteps < $1.roundTripSteps })
    }

    // MARK: - Formatting helpers

    /// A localized distance string (km or mi) for a meter value.
    static func distanceString(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road,
                                    numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    /// Fallback label when no reverse-geocoded name exists.
    static func coordinateLabel(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", c.latitude, c.longitude)
    }
}
