//
//  WatchHistoryView.swift
//  StepsWatch
//
//  The places history on the watch, synced from the phone (the visit log is
//  captured on iPhone and shipped as a compact digest via WatchConnectivity —
//  see WatchSync). Shows the current round-trip suggestion on top, then the
//  recent places. Tapping a place opens the watch Maps app with **walking
//  directions** to it — the watch stand-in for the iPhone's 3D flyover.
//

import SwiftUI
import MapKit
import CoreLocation

struct WatchHistoryView: View {
    @State private var digest = WatchSync.latestDigest
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { GridStyle.current.goalColor(for: scheme) }

    var body: some View {
        Group {
            if let digest, !digest.places.isEmpty {
                list(digest)
            } else {
                emptyState
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { digest = WatchSync.latestDigest }
        .onReceive(NotificationCenter.default.publisher(for: WatchSync.placesDidChange)) { _ in
            digest = WatchSync.latestDigest
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { digest = WatchSync.latestDigest }
        }
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("-STEPS_WATCH_DIRECTIONS"),
               let place = digest?.places.first(where: { !$0.isHome }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    openWalkingDirections(to: place)
                }
            }
            #endif
        }
    }

    // MARK: - List

    private func list(_ digest: WatchPlacesDigest) -> some View {
        List {
            // The round-trip nudge, if the phone found one. Tap to walk it in Maps.
            if let text = digest.suggestionText,
               let place = suggestionPlace(in: digest) {
                Section {
                    Button { openWalkingDirections(to: place) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "figure.walk")
                                .font(.footnote)
                                .foregroundStyle(accent)
                            Text(text)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                ForEach(digest.places) { place in
                    if place.isHome {
                        placeRow(place)         // home isn't a walk destination
                    } else {
                        Button { openWalkingDirections(to: place) } label: {
                            placeRow(place)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Places")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .textCase(nil)
            }
        }
    }

    private func placeRow(_ place: WatchPlace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(place.name)
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if place.isHome {
                    Image(systemName: "house.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
                if !place.isHome {
                    Image(systemName: "arrow.triangle.turn.up.right.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                }
            }
            Text(place.subtitle)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No places yet")
                .font(.system(.headline, design: .monospaced))
            Text("Open Steps on your iPhone to sync the places you've been.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func suggestionPlace(in digest: WatchPlacesDigest) -> WatchPlace? {
        guard let id = digest.suggestionPlaceID else { return nil }
        return digest.places.first(where: { $0.id == id })
    }

    /// Open the watch Maps app with walking directions from the user's location to
    /// the place. Maps supplies the current-location start; we pass the destination
    /// and the walking mode.
    private func openWalkingDirections(to place: WatchPlace) {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

#Preview {
    WatchHistoryView()
}
