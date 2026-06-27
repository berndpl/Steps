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
    /// The palette goal color, used as the app accent. Re-read whenever the grid
    /// style might have changed (launch, foreground, after customizing).
    @State private var accentColor = GridStyle.current.goalColor
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await load() } }
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showCustomize) { GridCustomizationView() }
        // Refresh the accent after the customizer closes (its writes land in the
        // App Group; re-read the current goal color so the app updates too).
        .onChange(of: showCustomize) { _, presented in
            if !presented { accentColor = GridStyle.current.goalColor }
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
        case .steps:      stepsView(8_432)
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
        }
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
            Text("Enable step access in Settings → Health → Data Access & Devices → Steps.")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(textMuted)
                .multilineTextAlignment(.center)
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
        accentColor = GridStyle.current.goalColor
        if HealthKitService.shared.needsAuthorizationPrompt {
            phase = .needsPermission
            return
        }
        do {
            let steps = try await HealthKitService.shared.todaySteps()
            phase = .ready(steps)
            // Sync recent history into the shared App Group cache, then refresh
            // the widget so it renders from the synced data.
            await HealthKitService.shared.refreshSharedCache()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            phase = .denied
        }
    }
}

#Preview {
    ContentView()
}
