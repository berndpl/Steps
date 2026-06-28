//
//  StepsAccessoryViews.swift
//  StepsWidget
//
//  Lock-screen accessory renderings (and, in a later phase, watch-face
//  complications — the views are written platform-agnostically so the watch
//  widget extension can reuse them as-is).
//
//  Accessory families render in a desaturated / vibrant tint mode, so these
//  views deliberately avoid the app's gold + green ramp: they lean on `Gauge`
//  and SF Symbols, which the system tints correctly. `AccessoryWidgetBackground`
//  supplies the subtle platform-appropriate backdrop where one is wanted.
//

import SwiftUI
import WidgetKit

/// Today's count with a goal-progress ring. The "Steps Ring" widget.
struct StepsRingView: View {
    let steps: Int
    @Environment(\.widgetFamily) private var family

    private var progress: Double {
        min(Double(steps) / Double(dailyStepGoal), 1.0)
    }

    /// Compact count, e.g. 6,240 → "6.2k", 940 → "940". Keeps the circular
    /// complication legible where the full number wouldn't fit.
    private var compactCount: String {
        if steps >= 1_000 {
            let k = Double(steps) / 1_000
            return String(format: "%.1fk", k)
        }
        return "\(steps)"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            // Inline is a single tinted line beside the time — text only.
            Text("\(steps.formatted()) steps")

        case .accessoryRectangular:
            HStack(spacing: 10) {
                ring
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Steps")
                        .font(.headline)
                    Text("\(steps.formatted()) / \(dailyStepGoal.formatted())")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

        default: // .accessoryCircular
            ring
        }
    }

    /// A circular progress ring (not a gauge) with the compact count centered.
    private var ring: some View {
        ProgressView(value: progress)
            .progressViewStyle(.circular)
            .overlay {
                Text(compactCount)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.6)
            }
    }
}

/// The "Tiny Steps" widget: no number, just the evolving stage symbol over a thin
/// progress ring — a single glyph that advances every 1,000 steps.
struct TinyStepsView: View {
    let steps: Int
    @Environment(\.widgetFamily) private var family

    private var currentStage: StepStage { stage(for: steps) }

    private var progress: Double {
        min(Double(steps) / Double(dailyStepGoal), 1.0)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            // Inline can't draw rings; show the symbol + a short progress label.
            Label("\(currentStage.thousands)k / 10k", systemImage: currentStage.symbol)

        case .accessoryRectangular:
            HStack(spacing: 10) {
                symbolOverRing
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tiny Steps")
                        .font(.headline)
                    Text("\(currentStage.thousands) / 10")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

        default: // .accessoryCircular
            symbolOverRing
        }
    }

    /// A circular progress ring with the current stage symbol centered inside.
    private var symbolOverRing: some View {
        ProgressView(value: progress)
            .progressViewStyle(.circular)
            .overlay {
                Image(systemName: currentStage.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .minimumScaleFactor(0.5)
            }
    }
}
