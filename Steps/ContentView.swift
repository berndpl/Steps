//
//  ContentView.swift
//  Steps
//
//  App style: notes-plontsch adapted to SwiftUI — Catppuccin Mocha (dark) /
//  Latte (light) surfaces, monospaced type throughout, flat (no shadows),
//  hierarchy from space + colour, not weight. Accent stays Steps gold.
//  (The widget keeps its own Spark/Letters style — see StepsWidget.)
//

import SwiftUI
import HealthKit
import WidgetKit

struct ContentView: View {
    private enum Phase {
        case loading
        case needsPermission
        case ready(Int)
        case denied
    }

    @State private var phase: Phase = .loading
    @State private var showSettings = false
    @State private var showCustomize = false
    @State private var showInbox = false
    @State private var showHistory = false
    /// Unread notification-history count, for the Inbox button badge.
    @State private var unreadCount = 0
    /// Per-activity time/distance for today, keyed by `DayActivity`. Drives the
    /// tappable badges and the detail line they reveal.
    @State private var activityDetails: [DayActivity: ActivityDetail] = [:]
    /// The badge the user tapped — reveals its time/distance (nil = none selected).
    @State private var selectedActivity: DayActivity?
    /// A round-trip suggestion for reaching today's goal (nil = none to show).
    @State private var suggestion: VisitDistance.Suggestion?
    @State private var showWalkFlyover = false
    /// The palette goal color, used as the app accent. Re-read whenever the grid
    /// style might have changed (launch, foreground, after customizing).
    @State private var accentColor = GridStyle.current.goalColor(for: .dark)
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    /// Milestone-alerts toggle, stored in the App Group so the background step
    /// observer reads the same value the settings sheet writes.
    @AppStorage(SettingsStore.notificationsEnabledKey, store: SettingsStore.defaults)
    private var notificationsEnabled = false

#if DEBUG
    // Running count for the DEBUG "Simulate +1,000 steps" action below.
    @State private var simulatedSteps = 0
#endif

    // notes-plontsch palette (via colorsets; Mocha dark / Latte light).
    private let textPrimary = Color("AppText")
    private let textMuted = Color("AppTextMuted")

#if DEBUG
    /// Lets every screen be reached during development. Compiled out of release
    /// builds, so the shipping app stays a single live view.
    enum PreviewMode: String, CaseIterable, Identifiable {
        case live = "Live"
        case permission = "Permission"
        case loading = "Loading"
        case steps = "Steps"
        case denied = "Denied"
        case grid = "Grid"
        var id: String { rawValue }
    }
    // Initial mode can be forced via launch arg `-STEPS_PREVIEW Grid` (also handy
    // as a Run scheme argument) so any screen opens directly for testing.
    @State private var previewMode: PreviewMode =
        PreviewMode(rawValue: UserDefaults.standard.string(forKey: "STEPS_PREVIEW") ?? "") ?? .live
#endif

    var body: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()

            content
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            settingsButton

#if DEBUG
            debugMenu
#endif
        }
        // Goal color ripples to the accent: the hero number (.tint), the CTA, and
        // today's grid ring. Background colorsets are untouched (stays neutral).
        .tint(accentColor)
        .task { await load() }
#if DEBUG
        // Open the Inbox directly for testing: launch arg `-STEPS_OPEN_INBOX 1`.
        // Seeds a few sample messages when the history is empty so the list is
        // demonstrable without waiting for real notifications.
        .onAppear {
            if UserDefaults.standard.string(forKey: "STEPS_OPEN_INBOX") == "1" {
                if NotificationLog.all().isEmpty {
                    let cal = Calendar.current
                    let now = Date()
                    func at(_ h: Int, _ m: Int) -> Date {
                        cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
                    }
                    NotificationLog.record(title: "🌅 First steps", body: "Good morning — you're moving!", date: at(7, 42))
                    NotificationLog.record(title: "🚶 3,000 steps", body: "Finding your rhythm.", date: at(11, 18))
                    NotificationLog.record(title: "🏃 5,000 steps", body: "Halfway — keep it up!", date: at(14, 5))
                    NotificationLog.record(title: "🔥 7-day streak!", body: "7 days at goal in a row. Keep it going!", date: at(14, 6))
                    NotificationLog.record(title: "🤏 So close!", body: "Just 700 steps to your 10,000-step goal — you're this close.", date: at(19, 30))
                }
                showInbox = true
            }
            // Seed sample visits (home + a few places) for testing History and the
            // Today suggestion without waiting for real CLVisit callbacks:
            // launch arg `-STEPS_SEED_VISITS 1`.
            if UserDefaults.standard.string(forKey: "STEPS_SEED_VISITS") == "1" {
                if VisitLog.all().isEmpty { Self.seedSampleVisits() }
                showHistory = true
            }
            // Open the Walk Flyover directly for testing/auditing the 3D fly-through:
            // launch arg `-STEPS_OPEN_FLYOVER 1`. Seeds sample visits when the log is
            // empty so a round-trip suggestion exists, resolves it, then presents the
            // flyover — a normally transient state made reachable for screenshots.
            if UserDefaults.standard.string(forKey: "STEPS_OPEN_FLYOVER") == "1" {
                if VisitLog.all().isEmpty { Self.seedSampleVisits() }
                Task {
                    if suggestion == nil {
                        suggestion = await VisitDistance.todaySuggestion(todaySteps: 8_432)
                    }
                    if suggestion != nil { showWalkFlyover = true }
                }
            }
        }
#endif
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await load() } }
        }
        .onChange(of: scheme) { _, _ in
            accentColor = GridStyle.current.goalColor(for: scheme)
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showCustomize) { GridCustomizationView() }
        .sheet(isPresented: $showInbox) { InboxView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .fullScreenCover(isPresented: $showWalkFlyover) {
            if let suggestion {
                WalkFlyoverView(suggestion: suggestion)
            }
        }
        // Refresh the accent after the customizer closes (its writes land in the
        // App Group; re-read the current goal color so the app updates too).
        .onChange(of: showCustomize) { _, presented in
            if !presented { accentColor = GridStyle.current.goalColor(for: scheme) }
        }
        // Clear the unread badge once the inbox has been opened and closed.
        .onChange(of: showInbox) { _, presented in
            if !presented { unreadCount = NotificationLog.unreadCount }
        }
    }

    // MARK: - Settings

    /// Top-leading gear + paintbrush, mirroring the DEBUG ladybug in the top-trailing corner.
    private var settingsButton: some View {
        VStack {
            HStack(spacing: 4) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(textMuted)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Settings")
                Button { showCustomize = true } label: {
                    Image(systemName: "paintbrush")
                        .foregroundStyle(textMuted)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Customize grid")
                Button { showInbox = true } label: {
                    Image(systemName: "tray")
                        .foregroundStyle(textMuted)
                        .padding(10)
                        .contentShape(Rectangle())
                        .overlay(alignment: .topTrailing) {
                            if unreadCount > 0 {
                                Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(.tint))
                                    .offset(x: -2, y: 6)
                            }
                        }
                }
                .accessibilityLabel("Inbox")
                Button { showHistory = true } label: {
                    Image(systemName: "map")
                        .foregroundStyle(textMuted)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("History")
                Spacer()
            }
            Spacer()
        }
        .padding(8)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Milestone alerts", isOn: $notificationsEnabled)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Tiny Steps")
                        .font(.system(.caption, design: .monospaced))
                } footer: {
                    Text("Get an encouraging notification every 1,000 steps toward your \(dailyStepGoal.formatted())-step goal.")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        // Ask for permission the moment alerts are switched on (iOS only prompts
        // once; later toggles are silent). Turning it off needs no permission.
        .onChange(of: notificationsEnabled) { _, enabled in
            if enabled { Task { await StepNotifier.shared.requestAuthorization() } }
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
#if DEBUG
        switch previewMode {
        case .live:       liveContent
        case .permission: permissionView
        case .loading:    loadingView
        case .steps:
            stepsView(8_432)
                .task {
                    if activityDetails.isEmpty {
                        activityDetails = [
                            .cycling: ActivityDetail(minutes: 42, distanceMeters: 12_300),
                            .strength: ActivityDetail(minutes: 35),
                            .mindful: ActivityDetail(minutes: 10),
                        ]
                    }
                    if suggestion == nil {
                        suggestion = await VisitDistance.todaySuggestion(todaySteps: 8_432)
                    }
                }
        case .denied:     deniedView
        case .grid:       gridPreview
        }
#else
        liveContent
#endif
    }

    @ViewBuilder
    private var liveContent: some View {
        switch phase {
        case .loading:        loadingView
        case .needsPermission: permissionView
        case .ready(let n):   stepsView(n)
        case .denied:         deniedView
        }
    }

    // MARK: - States

    private var loadingView: some View {
        ProgressView {
            Text("Reading Health…")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(textMuted)
        }
        .controlSize(.large)
        .tint(textMuted)
    }

    private func stepsView(_ steps: Int) -> some View {
        VStack(spacing: 10) {
            // Hierarchy from size + colour, not weight (notes-plontsch flattens weight).
            Text(steps, format: .number)
                .font(.system(size: 68, weight: .medium, design: .monospaced))
                .foregroundStyle(.tint)            // Steps gold
                .contentTransition(.numericText())
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: steps)
            Text("steps today")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(textMuted)

            // Today's activities as tappable badges. Tap one to reveal the time
            // and/or distance covered — cycling shows distance even when no formal
            // workout was recorded. Only activities logged today appear.
            if !activityDetails.isEmpty {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        ForEach(DayActivity.allCases.filter { activityDetails[$0] != nil }) { activity in
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    selectedActivity = (selectedActivity == activity) ? nil : activity
                                }
                            } label: {
                                Image(systemName: activity.symbol)
                                    .font(.system(size: 28))
                                    .foregroundStyle(.tint)
                                    .opacity(selectedActivity == nil || selectedActivity == activity ? 1 : 0.4)
                                    .scaleEffect(selectedActivity == activity ? 1.12 : 1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(activity.label)
                            .accessibilityValue(badgeDetailText(activity, activityDetails[activity] ?? ActivityDetail()))
                        }
                    }
                    if let sel = selectedActivity, let detail = activityDetails[sel] {
                        Text(badgeDetailText(sel, detail))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(textMuted)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            }

            // Nudge toward the goal: a known place whose round trip would close
            // today's gap. Populated from tracked visits (see VisitDistance).
            // Tap to fly the complete walk in 3D (see WalkFlyoverView).
            if let suggestion {
                Button {
                    showWalkFlyover = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("A round trip to \(suggestion.name) — about \(suggestion.roundTripSteps.formatted()) steps — would get you there.")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(textMuted)
                            .multilineTextAlignment(.center)
                        Image(systemName: "mountain.2")
                            .font(.system(size: 12))
                            .foregroundStyle(.tint)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: activityDetails)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: suggestion)
    }

    /// "Cycling · 5.4 km · 12 min" — the activity's name plus whichever metrics
    /// exist today. Distance is localized (km or mi) via `.road` usage.
    private func badgeDetailText(_ activity: DayActivity, _ d: ActivityDetail) -> String {
        var parts: [String] = []
        if d.distanceMeters > 0 {
            parts.append(Measurement(value: d.distanceMeters, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road,
                                        numberFormatStyle: .number.precision(.fractionLength(1)))))
        }
        if d.minutes > 0 { parts.append("\(d.minutes) min") }
        let detail = parts.joined(separator: " · ")
        return detail.isEmpty ? activity.label : "\(activity.label) · \(detail)"
    }

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Track your steps")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(textPrimary)
            Text("Steps reads your step count from Apple Health to show today's total and your home-screen grid.")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(textMuted)
                .multilineTextAlignment(.center)
            Button("Allow Health Access") {
                Task { await requestAccess() }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .font(.system(.body, design: .monospaced))
        }
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 46))
                .foregroundStyle(textMuted)
            Text("No step data")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(textPrimary)
            Text("Steps needs permission to read your step count from Apple Health. Grant it below, or turn it on in Settings › Apps › Steps › Health.")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(textMuted)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button("Allow Health Access") {
                    Task { await requestAccess() }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .font(.system(.body, design: .monospaced))
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .font(.system(.callout, design: .monospaced))
            }
            .padding(.top, 4)
        }
    }

#if DEBUG
    /// Renders the actual widget content inside the app, sized like a small
    /// widget, so the home-screen view is testable without granting Health.
    private var gridPreview: some View {
        VStack(spacing: 12) {
            Text("Widget preview · sample data")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(textMuted)
            StepsMonthView(dailySteps: HealthKitService.sampleDailySteps())
                .padding(12)
                .frame(width: 158, height: 158)
                .background(Color("AppTextMuted").opacity(0.12))   // flat surface, no shadow
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// Single DEBUG affordance (replaces the old bottom chip toolbar): a menu in
    /// the corner to jump to any screen state.
    private var debugMenu: some View {
        VStack {
            HStack {
                Spacer()
                Menu {
                    Picker("Preview state", selection: $previewMode) {
                        ForEach(PreviewMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Divider()
                    // Walk the milestone ladder without real steps: each tap adds
                    // 1,000 and re-evaluates, so notification copy is testable in
                    // the simulator. (Requires Milestone alerts enabled + allowed.)
                    Button("Simulate +1,000 steps (\(simulatedSteps.formatted()))") {
                        simulatedSteps += 1_000
                        StepNotifier.shared.evaluate(todaySteps: simulatedSteps)
                    }
                    Button("Reset simulated steps") {
                        simulatedSteps = 0
                        SettingsStore.lastNotifiedThousand = 0
                    }
                    Divider()
                    // Populate the visit log with sample places (home + a few
                    // destinations) so History and the Today suggestion are
                    // demonstrable without real CLVisit events.
                    Button("Seed sample visits") {
                        Self.seedSampleVisits()
                        Task { await load() }
                    }
                    Button("Clear visits") {
                        VisitLog.clear()
                        suggestion = nil
                    }
                } label: {
                    Image(systemName: "ladybug.fill")
                        .foregroundStyle(textMuted)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Debug preview state")
            }
            Spacer()
        }
        .padding(8)
    }

    /// Sample places for testing: a home base (with overnight dwell so it's
    /// detected as home) plus a few daytime destinations at real, walkable
    /// distances so MapKit can route a round trip.
    static func seedSampleVisits() {
        let cal = Calendar.current
        let now = Date()
        func at(_ dayOffset: Int, _ h: Int, _ m: Int) -> Date {
            let base = cal.date(byAdding: .day, value: dayOffset, to: now) ?? now
            return cal.date(bySettingHour: h, minute: m, second: 0, of: base) ?? base
        }
        // Home: Alexanderplatz-ish, occupied overnight.
        let home = Visit(latitude: 52.5219, longitude: 13.4132,
                         arrival: at(-1, 22, 0), departure: at(0, 7, 0),
                         horizontalAccuracy: 30, recordedAt: at(0, 7, 0),
                         name: "Home")
        // A close café (~1 km one way) and a farther park (~2.5 km one way).
        let cafe = Visit(latitude: 52.5290, longitude: 13.4010,
                         arrival: at(0, 10, 0), departure: at(0, 11, 0),
                         horizontalAccuracy: 30, recordedAt: at(0, 11, 0),
                         name: "Corner Café")
        let park = Visit(latitude: 52.5145, longitude: 13.3760,
                         arrival: at(0, 14, 0), departure: at(0, 15, 30),
                         horizontalAccuracy: 30, recordedAt: at(0, 15, 30),
                         name: "Tiergarten")
        for v in [park, cafe, home] { VisitLog.record(v) }
    }
#endif

    // MARK: - Actions

    private func requestAccess() async {
        phase = .loading   // show spinner; the Health dialog can take a moment
        do {
            try await HealthKitService.shared.requestAuthorization()
            // Now that access exists, start the observer so the widget stays
            // current without waiting for the next launch.
            HealthKitService.shared.startObservingSteps()
        } catch {
            // Ignore; load() below resolves the resulting state.
        }
        await load()
    }

    private func load() async {
        // Keep the accent in step with the current grid goal color.
        accentColor = GridStyle.current.goalColor(for: scheme)
        unreadCount = NotificationLog.unreadCount
        if HealthKitService.shared.needsAuthorizationPrompt {
            phase = .needsPermission
            return
        }
        // Ensure access to all read types we use — Workouts and Mindfulness were
        // added after steps, so users who granted steps earlier still need the
        // prompt for them (otherwise cycling minutes + activity badges stay empty).
        // Idempotent: iOS only prompts for not-yet-determined types.
        try? await HealthKitService.shared.requestAuthorization()
        do {
            let steps = try await HealthKitService.shared.todaySteps()
            phase = .ready(steps)
            // Sync recent history into the shared App Group cache, then refresh
            // the widget so it renders from the synced data.
            await HealthKitService.shared.refreshSharedCache()
            WidgetCenter.shared.reloadAllTimelines()
            activityDetails = await HealthKitService.shared.todayActivityDetails()
            if let sel = selectedActivity, activityDetails[sel] == nil { selectedActivity = nil }
            // Round-trip nudge from tracked visits (nil once at/over goal).
            suggestion = await VisitDistance.todaySuggestion(todaySteps: steps)
        } catch {
            phase = .denied
        }
    }
}

#Preview {
    ContentView()
}
