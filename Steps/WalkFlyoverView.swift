//
//  WalkFlyoverView.swift
//  Steps
//
//  An interactive 3D preview of a suggested round-trip walk. Tapping the Today
//  view's round-trip nudge opens this: MapKit fetches the real walking route
//  home → destination, we build the there-and-back path, and drive a camera
//  along it over photorealistic 3D imagery (`.hybrid(elevation:.realistic)`).
//
//  MapKit has no "fly a route" API. To make the tour *scrubbable* we build a
//  `KeyframeTimeline<FlyPose>` once — position follows the route and heading
//  follows the (smoothed) path — then evaluate it at an arbitrary time so a
//  progress slider can drive the camera back and forth. A play/pause loop
//  advances that same progress.
//
//  Tilt and zoom are held *constant* for the whole walk and are adjustable via
//  two sliders; the framing you dial in is persisted and reused next time.
//
//  notes-plontsch styling: monospaced labels, flat chrome, map provides colour.
//

import SwiftUI
import MapKit
import CoreLocation

struct WalkFlyoverView: View {
    @Environment(\.dismiss) private var dismiss

    let suggestion: VisitDistance.Suggestion

    /// One stop on the fly-through: a point on the route and the (smoothed)
    /// heading toward the next, with a duration proportional to segment length.
    private struct Anchor {
        let coordinate: CLLocationCoordinate2D
        let heading: Double
        let duration: Double
    }

    /// The animated camera state. Only position + heading are keyframed; tilt and
    /// zoom are applied constantly from the sliders below.
    private struct FlyPose {
        var center: CLLocationCoordinate2D
        var heading: Double
    }

    @State private var route: MKRoute?
    @State private var roundTripCoords: [CLLocationCoordinate2D] = []
    @State private var anchors: [Anchor] = []
    @State private var timeline: KeyframeTimeline<FlyPose>?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentCoord: CLLocationCoordinate2D?
    @State private var isLoading = true
    @State private var routeUnavailable = false

    /// Playback position along the walk, 0 (leaving) … 1 (back home).
    @State private var progress: Double = 0
    @State private var isPlaying = false
    @State private var playTask: Task<Void, Never>?

    /// Constant camera framing, held for the whole walk and persisted. Sourced
    /// from the user's own pinch/tilt/rotate gestures on the map — never sliders.
    @State private var tilt: Double = SettingsStore.flyoverTilt
    @State private var zoom: Double = SettingsStore.flyoverZoom
    /// Rotation the user has dialed in, added on top of the route's own heading.
    @State private var headingOffset: Double = SettingsStore.flyoverHeadingOffset
    /// The heading we last drove the camera to, used to tell our own frames apart
    /// from a user's rotate gesture.
    @State private var lastDrivenHeading: Double = 0
    /// True once the opening frame is seated, so the intro camera transition
    /// isn't mistaken for a user gesture.
    @State private var hasSeated = false

    private let textPrimary = Color("AppText")
    private let textMuted = Color("AppTextMuted")

    /// Total wall-clock length of a full play-through, in seconds.
    private let tourDuration: Double = 30

    /// Opening heading: the natural bearing along the first leg of the route.
    private var routeStartHeading: Double {
        guard roundTripCoords.count > 1 else { return 0 }
        return Self.bearing(from: roundTripCoords[0], to: roundTripCoords[1])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                map
                if isLoading { loadingOverlay }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) { infoCard }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .task { await prepare() }
        .onChange(of: progress) { _, p in applyProgress(p) }
        .onDisappear { playTask?.cancel() }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition) {
            if let route {
                MapPolyline(route.polyline)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            } else if routeUnavailable {
                MapPolyline(coordinates: [suggestion.home, suggestion.destination])
                    .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 4, dash: [6, 6]))
            }
            Marker("Home", systemImage: "house.fill", coordinate: suggestion.home)
                .tint(Color.accentColor)
            Marker(suggestion.name, systemImage: "mappin", coordinate: suggestion.destination)
                .tint(.red)
            if let currentCoord {
                Annotation("", coordinate: currentCoord) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 2)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .onMapCameraChange(frequency: .continuous) { context in
            adoptGestureFraming(from: context.camera)
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color("AppBackground").opacity(0.75).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                Text("Plotting the walk…")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(textMuted)
            }
        }
    }

    // MARK: - Info card (title + transport + framing)

    /// The controls, floating in a frosted rounded card just above the home
    /// indicator so the 3D map reads as uninterrupted full-screen imagery —
    /// map shows above, beside, and beneath the card.
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.name)
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(textMuted)
            }
            transport
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.tint)
                    .frame(width: 28)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            Slider(value: $progress, in: 0...1) { editing in
                if editing { pause() }
            }
            .tint(.accentColor)
            .disabled(isLoading)

            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(textMuted)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var detailLine: String {
        let distance = VisitDistance.distanceString(suggestion.roundTripMeters)
        return "\(distance) · ~\(suggestion.roundTripSteps.formatted()) steps round trip"
    }

    // MARK: - Preparation

    private func prepare() async {
        cameraPosition = .region(regionCovering([suggestion.home, suggestion.destination]))

        let fetched = await VisitDistance.walkingRoute(from: suggestion.home, to: suggestion.destination)
        if let fetched {
            route = fetched
            roundTripCoords = Self.roundTrip(from: fetched.polyline)
        } else {
            routeUnavailable = true
            roundTripCoords = [suggestion.home, suggestion.destination, suggestion.home]
        }
        rebuildTimeline()
        isLoading = false

#if DEBUG
        // Screenshot-only: seat a static, pulled-back camera that frames the whole
        // round-trip walk (both markers + the route line) for the project-site hero,
        // instead of auto-flying the close-up tour. Launch arg `-STEPS_FLYOVER_OVERVIEW 1`.
        // hasSeated stays false so this framing is never adopted/persisted as the
        // user's real flyover zoom.
        if UserDefaults.standard.string(forKey: "STEPS_FLYOVER_OVERVIEW") == "1" {
            seatOverviewCamera()
            return
        }
#endif

        // Seat the opening frame, then auto-play once. Only after the intro
        // transition settles do we start honouring pinch/tilt gestures, so the
        // region→camera animation isn't mistaken for the user reframing.
        applyProgress(0)
        try? await Task.sleep(for: .milliseconds(600))
        hasSeated = true
        play()
    }

#if DEBUG
    /// Frame the entire walk in one static, gently-tilted overview: center on the
    /// route's bounding box, pull the camera back far enough to fit it, and look
    /// along the home→destination bearing so the path leads into the scene.
    private func seatOverviewCamera() {
        let coords = roundTripCoords.isEmpty ? [suggestion.home, suggestion.destination] : roundTripCoords
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLon = coords[0].longitude, maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let extent = CLLocation(latitude: maxLat, longitude: minLon)
            .distance(from: CLLocation(latitude: minLat, longitude: maxLon))
        let distance = max(extent * 1.9, 650)
        let heading = Self.bearing(from: suggestion.home, to: suggestion.destination)
        currentCoord = suggestion.home
        lastDrivenHeading = heading
        cameraPosition = .camera(MapCamera(centerCoordinate: center,
                                           distance: distance,
                                           heading: heading,
                                           pitch: 50))
    }
#endif

    /// (Re)build the anchors + keyframe timeline from the current route.
    private func rebuildTimeline() {
        anchors = Self.anchors(from: roundTripCoords,
                               totalDuration: tourDuration,
                               startHeading: routeStartHeading)
        guard let first = anchors.first else { timeline = nil; return }

        let anchorsLocal = anchors
        timeline = KeyframeTimeline(initialValue: FlyPose(center: first.coordinate,
                                                          heading: routeStartHeading)) {
            KeyframeTrack(\FlyPose.center) {
                for a in anchorsLocal { CubicKeyframe(a.coordinate, duration: a.duration) }
            }
            KeyframeTrack(\FlyPose.heading) {
                for a in anchorsLocal { CubicKeyframe(a.heading, duration: a.duration) }
            }
        }
    }

    /// Evaluate the timeline at `p` (0…1) and push the pose into the map camera,
    /// applying the constant tilt + zoom and the user's rotation offset.
    private func applyProgress(_ p: Double) {
        guard let timeline else { return }
        let pose = timeline.value(time: max(0, min(1, p)) * timeline.duration)
        currentCoord = pose.center
        let heading = Self.normalize(pose.heading + headingOffset)
        lastDrivenHeading = heading
        cameraPosition = .camera(MapCamera(centerCoordinate: pose.center,
                                           distance: zoom,
                                           heading: heading,
                                           pitch: tilt))
    }

    // MARK: - Playback

    private func togglePlay() { isPlaying ? pause() : play() }

    private func play() {
        guard !isLoading else { return }
        if progress >= 1 { progress = 0 }
        isPlaying = true
        playTask?.cancel()
        playTask = Task { @MainActor in
            var last = Date()
            while !Task.isCancelled && isPlaying && progress < 1 {
                try? await Task.sleep(for: .milliseconds(16))
                let now = Date()
                let dt = now.timeIntervalSince(last)
                last = now
                progress = min(1, progress + dt / tourDuration)
            }
            if progress >= 1 { isPlaying = false }
        }
    }

    private func pause() {
        isPlaying = false
        playTask?.cancel()
    }

    // MARK: - Framing (gesture-driven)

    /// Adopt the framing the user dials in by pinching / two-finger-tilting /
    /// rotating the map, and persist it for future flyovers. During our own
    /// playback the camera reports back the tilt/zoom we set (both constant), so
    /// those frames are no-ops. Rotation is captured only while paused — the
    /// per-frame heading changes of an active tour would otherwise be mistaken
    /// for a gesture — by comparing against the heading we last drove to.
    private func adoptGestureFraming(from camera: MapCamera) {
        guard hasSeated else { return }

        let newTilt = camera.pitch
        let newZoom = camera.distance
        if abs(newTilt - tilt) > 0.75 || abs(newZoom - zoom) > max(2, zoom * 0.01) {
            tilt = newTilt
            zoom = newZoom
            SettingsStore.flyoverTilt = newTilt
            SettingsStore.flyoverZoom = newZoom
        }

        if !isPlaying {
            let delta = Self.angularDelta(from: lastDrivenHeading, to: camera.heading)
            if abs(delta) > 0.75 {
                headingOffset += delta
                lastDrivenHeading = camera.heading
                SettingsStore.flyoverHeadingOffset = headingOffset
            }
        }
    }

    /// Heading in [0, 360).
    private static func normalize(_ deg: Double) -> Double {
        let m = deg.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }

    /// Shortest signed angle (degrees) from `a` to `b`, in (-180, 180].
    private static func angularDelta(from a: Double, to b: Double) -> Double {
        ((b - a + 540).truncatingRemainder(dividingBy: 360)) - 180
    }

    private func regionCovering(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coords.first else {
            return MKCoordinateRegion(center: suggestion.destination,
                                      span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.005),
                                    longitudeDelta: max((maxLon - minLon) * 1.5, 0.005))
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: - Route → anchors (static geometry)

    /// The full there-and-back coordinate path: the route's coordinates followed
    /// by the same coordinates reversed (minus the duplicated turnaround point).
    private static func roundTrip(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                              count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        guard coords.count > 1 else { return coords }
        let back = coords.dropLast().reversed()
        return coords + back
    }

    /// Decimate a coordinate path into ~24 anchors, each with a heading (toward
    /// the next) and a duration proportional to its segment length. Headings are
    /// **unwrapped** into a continuous chain from `startHeading` (so rotation
    /// always takes the short way, never spinning through the 0/360 seam) and
    /// then **smoothed** so the camera eases lazily around corners instead of
    /// snapping — turns feel gentle and forgiving.
    private static func anchors(from coords: [CLLocationCoordinate2D],
                                totalDuration: Double,
                                startHeading: Double,
                                target: Int = 24) -> [Anchor] {
        guard coords.count > 1 else {
            return coords.map { Anchor(coordinate: $0, heading: startHeading, duration: totalDuration) }
        }

        let stride = max(1, coords.count / target)
        var picked: [CLLocationCoordinate2D] = []
        var i = 0
        while i < coords.count {
            picked.append(coords[i])
            i += stride
        }
        if let last = coords.last,
           picked.last.map({ !Self.same($0, last) }) ?? true {
            picked.append(last)
        }
        guard picked.count > 1 else {
            return [Anchor(coordinate: picked[0], heading: startHeading, duration: totalDuration)]
        }

        var rawHeadings: [Double] = []
        for idx in picked.indices {
            if idx < picked.count - 1 {
                rawHeadings.append(bearing(from: picked[idx], to: picked[idx + 1]))
            } else {
                rawHeadings.append(rawHeadings.last ?? startHeading)
            }
        }
        var unwrapped: [Double] = []
        var prev = startHeading
        for h in rawHeadings {
            let delta = ((h - prev + 540).truncatingRemainder(dividingBy: 360)) - 180
            prev += delta
            unwrapped.append(prev)
        }
        let smoothed = smooth(unwrapped, passes: 3)
        // Anticipate turns gently: shift the heading series one anchor earlier so
        // the camera *begins* easing toward the upcoming direction just before the
        // corner — enough to read smooth, without swinging away too soon.
        let lead = 1
        let anticipated = smoothed.indices.map { smoothed[min($0 + lead, smoothed.count - 1)] }

        var segLengths: [Double] = []
        for idx in 0..<(picked.count - 1) {
            let a = CLLocation(latitude: picked[idx].latitude, longitude: picked[idx].longitude)
            let b = CLLocation(latitude: picked[idx + 1].latitude, longitude: picked[idx + 1].longitude)
            segLengths.append(max(a.distance(from: b), 1))
        }
        let totalLength = segLengths.reduce(0, +)
        let firstSlice = min(0.5, totalDuration * 0.02)
        let movingDuration = max(totalDuration - firstSlice, 0.1)

        var result: [Anchor] = []
        for idx in picked.indices {
            let duration: Double
            if idx == 0 {
                duration = firstSlice
            } else {
                let share = segLengths[idx - 1] / totalLength
                duration = max(movingDuration * share, 0.2)
            }
            result.append(Anchor(coordinate: picked[idx], heading: anticipated[idx], duration: duration))
        }
        return result
    }

    /// Neighbour-averaging low-pass over a continuous (unwrapped) heading series.
    /// Each pass rounds off sharp corners so the camera's turn feels lazy and
    /// smooth; endpoints are held fixed so the walk still starts/ends true.
    private static func smooth(_ values: [Double], passes: Int) -> [Double] {
        guard values.count > 2 else { return values }
        var current = values
        for _ in 0..<passes {
            var next = current
            for idx in 1..<(current.count - 1) {
                next[idx] = current[idx - 1] * 0.25 + current[idx] * 0.5 + current[idx + 1] * 0.25
            }
            current = next
        }
        return current
    }

    private static func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 1e-7 && abs(a.longitude - b.longitude) < 1e-7
    }

    /// Initial compass bearing from one coordinate to another, in degrees [0, 360).
    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }
}
