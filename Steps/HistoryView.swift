//
//  HistoryView.swift
//  Steps
//
//  Where you stay and where you go. Lists the places Core Location's visit
//  monitoring has recorded (see VisitLog), grouped into distinct spots, with the
//  round-trip walking cost home ↔ there shown as both distance and estimated
//  steps — the raw material for the Today view's "a round trip would get you
//  there" nudge.
//
//  Tracking is opt-in: with no Always grant yet, the empty state offers a button
//  that deliberately triggers the location prompt.
//  notes-plontsch styling: monospaced, flat, hierarchy from space + colour.
//

import SwiftUI
import CoreLocation
import MapKit

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss

    /// Per-place round-trip cost, resolved lazily via MapKit.
    private struct Trip: Equatable {
        var meters: Double
        var steps: Int
    }

    @State private var clusters: [VisitCluster] = []
    @State private var homeID: UUID?
    @State private var trips: [UUID: Trip] = [:]
    @State private var isAuthorized = LocationService.shared.isAuthorized
    @State private var canRequest = LocationService.shared.canRequestAccess

    /// The place tapped in the list, shown on a map sheet.
    @State private var selectedCluster: VisitCluster?

    private let textPrimary = Color("AppText")
    private let textMuted = Color("AppTextMuted")

    var body: some View {
        NavigationStack {
            Group {
                if clusters.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color("AppBackground"))
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .task { reload(); await resolveTrips() }
        // Refresh when a background visit lands while the sheet is open.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            reload()
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(groupedClusters, id: \.day) { group in
                Section {
                    ForEach(group.items) { cluster in
                        Button {
                            selectedCluster = cluster
                        } label: {
                            row(for: cluster)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color("AppBackground"))
                    }
                } header: {
                    Text(dayLabel(group.day))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(textMuted)
                        .textCase(nil)
                }
            }

            Section {
                Button(role: .destructive) {
                    VisitLog.clear()
                    reload()
                } label: {
                    Label("Clear history", systemImage: "trash")
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .listRowBackground(Color("AppBackground"))
                .listRowSeparator(.hidden)
            }

            Section {
                Text(privacyFooter)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .listRowBackground(Color("AppBackground"))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .sheet(item: $selectedCluster) { cluster in
            VisitMapView(title: cluster.name ?? VisitDistance.coordinateLabel(cluster.coordinate),
                         subtitle: detailLine(for: cluster, isHome: cluster.id == homeID),
                         coordinate: cluster.coordinate,
                         isHome: cluster.id == homeID)
        }
    }

    /// Privacy-forward explainer shown at the foot of the list: what's captured,
    /// where it lives, and the soft bias toward places you likely dwell at.
    private let privacyFooter = """
    How this works: Steps uses Apple's low-power visit detection to notice where you \
    dwell, then measures the round trip home ↔ there to suggest walks that reach your \
    goal. Your places stay on this device — the only thing sent out is an anonymous \
    map lookup to name each spot and measure walking distance.

    When naming a place, Steps leans toward the kinds of spots you likely spend time at \
    — supermarkets, parks and playgrounds, and gyms — so a stay reads as the venue you \
    were at rather than a pin that happens to sit a few metres closer.
    """

    /// Clusters bucketed by calendar day of their most recent visit, newest first.
    private var groupedClusters: [(day: Date, items: [VisitCluster])] {
        let cal = Calendar.current
        return Dictionary(grouping: clusters) { cal.startOfDay(for: $0.lastSeen) }
            .map { (day: $0.key, items: $0.value.sorted { $0.lastSeen > $1.lastSeen }) }
            .sorted { $0.day > $1.day }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    @ViewBuilder
    private func row(for cluster: VisitCluster) -> some View {
        let isHome = cluster.id == homeID
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(cluster.name ?? VisitDistance.coordinateLabel(cluster.coordinate))
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                if isHome {
                    Image(systemName: "house.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tint)
                }
                Spacer(minLength: 8)
                Text(cluster.lastSeen, format: .dateTime.hour().minute())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(textMuted)
            }
            // The round-trip cost line — the point of this whole feature.
            HStack(spacing: 4) {
                Text(detailLine(for: cluster, isHome: isHome))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(textMuted)
                Spacer(minLength: 4)
                Image(systemName: "map")
                    .font(.system(size: 10))
                    .foregroundStyle(textMuted)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    /// "Home base" for home; otherwise "2.4 km · ~3,300 steps round trip", or a
    /// resolving/visit-count placeholder until MapKit answers.
    private func detailLine(for cluster: VisitCluster, isHome: Bool) -> String {
        if isHome { return "Home base" }
        if let trip = trips[cluster.id] {
            return "\(VisitDistance.distanceString(trip.meters)) · ~\(trip.steps.formatted()) steps round trip"
        }
        let visits = cluster.visitCount == 1 ? "1 visit" : "\(cluster.visitCount) visits"
        return "\(visits) · measuring round trip…"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundStyle(textMuted)
            Text(isAuthorized ? "No places yet" : "Track your visits")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(textPrimary)
            Text(isAuthorized
                 ? "As you go about your day, the places you spend time at appear here — with how far it is to walk there and back."
                 : "Steps can track where you dwell (using Apple's low-power visit detection) to suggest round trips that reach your daily goal. Nothing leaves your phone except map lookups for distance and place names.")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !isAuthorized && canRequest {
                Button("Track my visits") {
                    LocationService.shared.requestAccess()
                    // Re-read after the prompt resolves.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isAuthorized = LocationService.shared.isAuthorized
                        canRequest = LocationService.shared.canRequestAccess
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .font(.system(.body, design: .monospaced))
                .padding(.top, 4)
            } else if !isAuthorized && !canRequest {
                Text("Enable Always location for Steps in Settings → Privacy → Location Services.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func reload() {
        clusters = VisitLog.clusters()
        homeID = VisitDistance.homeCluster(from: clusters)?.id
        isAuthorized = LocationService.shared.isAuthorized
        canRequest = LocationService.shared.canRequestAccess
    }

    /// Resolve the round-trip walking cost for every non-home place (cached, so
    /// this is a no-op after the first pass).
    private func resolveTrips() async {
        guard let homeID,
              let home = clusters.first(where: { $0.id == homeID }) else { return }
        for cluster in clusters where cluster.id != homeID {
            if let result = await VisitDistance.resolveRoundTrip(for: cluster, home: home.coordinate) {
                trips[cluster.id] = Trip(meters: result.meters, steps: result.steps)
            }
        }
        // Distances are freshly cached now — push the enriched digest to the watch.
        WatchSync.shared.refreshPlaces()
    }
}

/// A place shown on a map. Presented when a History row is tapped, centered on
/// the recorded coordinate with a single annotation. notes-plontsch styling:
/// monospaced labels, flat chrome, the map itself providing the colour.
private struct VisitMapView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let isHome: Bool

    @State private var position: MapCameraPosition

    private let textPrimary = Color("AppText")
    private let textMuted = Color("AppTextMuted")

    init(title: String, subtitle: String, coordinate: CLLocationCoordinate2D, isHome: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.isHome = isHome
        _position = State(initialValue: .region(
            MKCoordinateRegion(center: coordinate,
                               span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
        ))
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                Marker(title, systemImage: isHome ? "house.fill" : "mappin",
                       coordinate: coordinate)
                    .tint(Color.accentColor)
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.thinMaterial)
            }
            .navigationTitle("Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }
}

#Preview {
    HistoryView()
}
