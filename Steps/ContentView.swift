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
    @Environment(\.scenePhase) private var scenePhase

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

#if DEBUG
            debugMenu
#endif
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await load() } }
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
        } catch {
            // Ignore; load() below resolves the resulting state.
        }
        await load()
    }

    private func load() async {
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
