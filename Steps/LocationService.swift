//
//  LocationService.swift
//  Steps
//
//  Core Location visit monitoring — the low-power way to learn where you dwell
//  without continuously burning GPS. The system decides when you've arrived at
//  or left a place and wakes the app (even from the background) with a `CLVisit`,
//  which we record into `VisitLog`.
//
//  Visit monitoring needs **Always** authorization. We never request it at
//  launch: a button in the app (see HistoryView) calls `requestAccess()` so the
//  prompt is a deliberate user choice. `startMonitoringIfAuthorized()` is called
//  at launch and simply no-ops until that grant exists.
//
//  App target only — the widget and watch don't track location.
//

import Foundation
import CoreLocation

final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()

    /// Called on the main thread whenever the log changes, so the UI can refresh.
    var onVisitsUpdate: (() -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
        // We don't need meter-level accuracy for dwell detection.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Let iOS relaunch us into the background for visit events.
        manager.allowsBackgroundLocationUpdates = false
    }

    /// Current authorization status.
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// True once the user has granted Always — the only state where visit
    /// monitoring actually delivers events.
    var isAuthorized: Bool { manager.authorizationStatus == .authorizedAlways }

    /// Whether it still makes sense to show an "enable" button (i.e. we haven't
    /// been permanently denied and aren't already fully granted).
    var canRequestAccess: Bool {
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse: return true
        default: return false
        }
    }

    /// Deliberately triggered from a button in the UI. Requests Always (iOS may
    /// first grant When-In-Use, then later ask to keep Always — expected). Starts
    /// monitoring as soon as the grant lands (see the delegate callback).
    func requestAccess() {
        manager.requestAlwaysAuthorization()
        startMonitoringIfAuthorized()
    }

    /// Begin visit monitoring if — and only if — Always is already granted.
    /// Safe to call at launch; no-ops otherwise.
    func startMonitoringIfAuthorized() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable(),
              isAuthorized else { return }
        manager.startMonitoringVisits()
    }

    /// Stop delivering visit events.
    func stopMonitoring() {
        manager.stopMonitoringVisits()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Kick off monitoring the moment Always is granted (or stop if revoked).
        if isAuthorized {
            startMonitoringIfAuthorized()
        } else {
            stopMonitoring()
        }
        DispatchQueue.main.async { self.onVisitsUpdate?() }
    }

    func locationManager(_ manager: CLLocationManager, didVisit clVisit: CLVisit) {
        // A zero-coordinate visit is Core Location noise — ignore it.
        guard CLLocationCoordinate2DIsValid(clVisit.coordinate),
              clVisit.coordinate.latitude != 0 || clVisit.coordinate.longitude != 0 else { return }

        // `distantPast`/`distantFuture` are Core Location's "unknown" sentinels.
        let arrival = clVisit.arrivalDate == .distantPast ? nil : clVisit.arrivalDate
        let departure = clVisit.departureDate == .distantFuture ? nil : clVisit.departureDate

        let visit = Visit(
            latitude: clVisit.coordinate.latitude,
            longitude: clVisit.coordinate.longitude,
            arrival: arrival,
            departure: departure,
            horizontalAccuracy: clVisit.horizontalAccuracy
        )
        VisitLog.record(visit)

        // Resolve a human-readable name in the background, fire a notification
        // for the detected visit, then notify the UI.
        Task {
            await VisitDistance.resolveName(for: visit)
            let resolved = VisitLog.all().first(where: { $0.id == visit.id }) ?? visit
            StepNotifier.shared.postVisit(resolved)
            await MainActor.run { self.onVisitsUpdate?() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Visit monitoring failures are non-fatal; nothing to do but ignore.
    }
}
