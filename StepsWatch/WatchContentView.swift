//
//  WatchContentView.swift
//  StepsWatch
//
//  A simple at-a-glance ring of today's steps toward the goal. Requests HealthKit
//  access on the watch and refreshes on activation.
//

import SwiftUI

struct WatchContentView: View {
    @State private var steps = 0
    @Environment(\.scenePhase) private var scenePhase

    // Steps gold (the app's accent); literal here since the asset/extension
    // colors live in the iOS targets.
    private let gold = Color(.sRGB, red: 0.96, green: 0.65, blue: 0.14)

    private var progress: Double { min(Double(steps) / Double(dailyStepGoal), 1) }

    var body: some View {
        VStack(spacing: 6) {
            Gauge(value: progress) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(steps, format: .number)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(gold)
            .frame(width: 120, height: 120)

            Text("steps today")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private func load() async {
        try? await HealthKitService.shared.requestAuthorization()
        if let s = try? await HealthKitService.shared.todaySteps() { steps = s }
    }
}
