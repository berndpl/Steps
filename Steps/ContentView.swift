//
//  ContentView.swift
//  Steps
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

#if DEBUG
    /// Lets every screen be reached with one tap during development. Compiled
    /// out of release builds, so the shipping app stays a single live view.
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
            content
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

#if DEBUG
            VStack {
                Spacer()
                previewSwitcher
            }
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
        ProgressView("Reading Health…")
            .controlSize(.large)
    }

    private func stepsView(_ steps: Int) -> some View {
        VStack(spacing: 8) {
            Text(steps, format: .number)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
                .animation(.snappy, value: steps)
            Text("steps today")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Track your steps")
                .font(.title2.bold())
            Text("Steps reads your step count from Apple Health to show today's total and your home-screen grid.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Allow Health Access") {
                Task { await requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No step data")
                .font(.title2.bold())
            Text("Enable step access in Settings → Health → Data Access & Devices → Steps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

#if DEBUG
    /// Renders the actual widget grid inside the app, sized like a small widget,
    /// so the home-screen view is testable without granting Health or seeding data.
    private var gridPreview: some View {
        VStack(spacing: 12) {
            Text("Widget preview · sample data")
                .font(.caption)
                .foregroundStyle(.secondary)
            StepsGridView(dailySteps: HealthKitService.sampleDailySteps())
                .padding(12)
                .frame(width: 158, height: 158)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
    }

    private var previewSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PreviewMode.allCases) { mode in
                    Button(mode.rawValue) { previewMode = mode }
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(previewMode == mode ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: Capsule())
                        .foregroundStyle(previewMode == mode ? .white : .primary)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(.thinMaterial)
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
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            phase = .denied
        }
    }
}

#Preview {
    ContentView()
}
