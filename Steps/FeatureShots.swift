//
//  FeatureShots.swift
//  Steps
//
//  Square (1:1) SwiftUI previews that spotlight a single part of the app, one
//  per "Features" row on the project site. These are *real* views built from the
//  same components the app ships (the contribution grid, activity badges, the
//  round-trip suggestion) — never a mockup — so the site's feature tiles stay
//  honest and age with the product.
//
//  Rendered headlessly to PNG via `ImageRenderer` when the app is launched with
//  the DEBUG arg `-STEPS_RENDER_FEATURES 1` (see ContentView). The `#Preview`
//  blocks below let the same squares be inspected live in Xcode's canvas.
//
//  DEBUG-only: the whole file compiles out of release.
//

#if DEBUG
import SwiftUI

// MARK: - Shared look

private enum FeaturePalette {
    /// Site-matching rose grid (Catppuccin Mocha rose accent), circular day cells
    /// for a calmer, less busy read. Ramp is a tonal rose; goal days pop in the
    /// site's exact accent hue.
    static let grid = GridStyle(
        rampHex: "#BE185D",
        goalHex: "#F38BA8",
        todayHex: "#F38BA8",
        curve: .easeIn,
        spread: 0.55,
        shape: .circle,
        marker: .dot
    )
    static let rose = Color(hex: "#F38BA8")     // site accent
    static let ink = Color(hex: "#CDD6F4")      // Catppuccin text
    static let muted = Color(hex: "#A6ADC8")    // Catppuccin subtext0
    static let card = Color(hex: "#242438")     // slightly lifted off the site base
    static let hairline = Color(hex: "#45475A") // Catppuccin surface1
}

/// Dark rounded tile the feature content sits on, so each square reads as its own
/// card on the site's base background. A tighter default padding lets the content
/// fill the square (the site downscales the render, so bigger content reads better).
private struct FeatureTile<Content: View>: View {
    var padding: CGFloat = 30
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 64, style: .continuous)
                .fill(FeaturePalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 64, style: .continuous)
                        .strokeBorder(FeaturePalette.hairline.opacity(0.6), lineWidth: 1.5)
                )
            content
                .padding(padding)
        }
        .frame(width: 640, height: 640)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Shared sample month

/// Deterministic, densely-filled month used by the grid + watch feature tiles, so
/// both read as a rich rose gradient (the sparse real-month sample goes near-black
/// on a dark tile). One clear best day gives the marker a home.
private enum FeatureSample {
    /// Anchor "today" on the month's last day so the whole month reads as filled
    /// (no faint future-day band at the bottom).
    static var referenceDay: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let interval = cal.dateInterval(of: .month, for: today),
              let dayCount = cal.range(of: .day, in: .month, for: today)?.count,
              let last = cal.date(byAdding: .day, value: dayCount - 1, to: interval.start)
        else { return today }
        return last
    }

    static var denseMonth: [Date: Int] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: Date()),
              let dayCount = cal.range(of: .day, in: .month, for: Date())?.count else { return [:] }
        let pattern = [7, 10, 12, 8, 11, 6, 9, 13, 7, 10, 5, 12, 8, 11, 9,
                       6, 13, 10, 7, 12, 8, 5, 11, 9, 13, 6, 10, 8, 12, 7, 11]
        var out: [Date: Int] = [:]
        for day in 0..<dayCount {
            guard let date = cal.date(byAdding: .day, value: day, to: interval.start) else { continue }
            out[cal.startOfDay(for: date)] = (day == 16 ? 15 : pattern[day % pattern.count]) * 1_000
        }
        return out
    }
}

// MARK: - 1. A widget you can make your own

struct FeatureGridSquare: View {
    /// Rows the current month spans (mirrors StepsGridView's MonthLayout), so the
    /// grid frame can be sized to hug exactly those rows inside the square tile.
    private static var monthRows: Int {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: FeatureSample.referenceDay),
              let days = cal.range(of: .day, in: .month, for: FeatureSample.referenceDay)?.count else { return 6 }
        let weekday = cal.component(.weekday, from: interval.start)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        return Int(ceil(Double(leading + days) / 7.0))
    }

    /// Height that `monthRows` of square cells occupy at the tile's content width
    /// (640 − 2×44 padding = 552), using StepsGridView's 4%-of-width spacing.
    private static var gridHeight: CGFloat {
        let w: CGFloat = 552
        let rows = CGFloat(monthRows)
        let cell = (w - w * 0.04 * 6) / 7          // (width − 6 gaps) / 7 columns
        return cell * rows + w * 0.04 * (rows - 1) // rows + inter-row gaps
    }

    var body: some View {
        FeatureTile(padding: 44) {
            StepsGridView(dailySteps: FeatureSample.denseMonth,
                          style: FeaturePalette.grid,
                          referenceDate: FeatureSample.referenceDay)
                .frame(maxWidth: .infinity)
                .frame(height: Self.gridHeight)
        }
    }
}

// MARK: - 2. More than steps

struct FeatureActivitiesSquare: View {
    private let activities: [DayActivity] = [.cycling, .strength, .mindful]

    var body: some View {
        FeatureTile {
            VStack(spacing: 26) {
                Spacer(minLength: 0)
                Text(8_432, format: .number)
                    .font(.system(size: 132, weight: .medium, design: .monospaced))
                    .foregroundStyle(FeaturePalette.rose)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("steps today")
                    .font(.system(size: 40, weight: .regular, design: .monospaced))
                    .foregroundStyle(FeaturePalette.muted)
                HStack(spacing: 40) {
                    ForEach(activities) { activity in
                        Image(systemName: activity.symbol)
                            .font(.system(size: 88))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(FeaturePalette.rose)
                    }
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 3. A walk that reaches your goal

struct FeatureWalkSquare: View {
    var body: some View {
        FeatureTile {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 104))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(FeaturePalette.rose)
                Text("1,568 to your goal")
                    .font(.system(size: 34, weight: .regular, design: .monospaced))
                    .foregroundStyle(FeaturePalette.muted)
                Text("A round trip to **Riverside Park** — about 3,200 steps — would get you there.")
                    .font(.system(size: 34, weight: .regular, design: .monospaced))
                    .foregroundStyle(FeaturePalette.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk")
                    Text("2.3 km round trip")
                }
                .font(.system(size: 28, weight: .regular, design: .monospaced))
                .foregroundStyle(FeaturePalette.rose)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 4. On your wrist

struct FeatureWatchSquare: View {
    var body: some View {
        FeatureTile {
            // The real watch home layout (shared StepsGridView + count + badges)
            // inside a watch-shaped frame, so the tile reads as "the app on your
            // wrist" — distinct from the flat home-screen widget in the first tile.
            // A late reference day fills the month; count is pinned to the canonical
            // 8.432 the whole site uses.
            watchContent
                .padding(22)
                .frame(width: 344, height: 410)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 92, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 92, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
                .environment(\.colorScheme, .dark)
        }
    }

    private var watchContent: some View {
        let goal = FeaturePalette.grid.goalColor(for: .dark)
        return VStack(spacing: 8) {
            StepsGridView(dailySteps: FeatureSample.denseMonth,
                          style: FeaturePalette.grid,
                          referenceDate: FeatureSample.referenceDay)
            HStack(spacing: 4) {
                Text(8_432, format: .number)
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(goal)
                Spacer(minLength: 4)
                ForEach([DayActivity.cycling, .strength]) { activity in
                    Image(systemName: activity.symbol)
                        .font(.footnote)
                        .foregroundStyle(goal)
                }
            }
        }
    }
}

// MARK: - Headless PNG renderer

@MainActor
enum FeatureShots {
    /// Render each square to a PNG in the app's Documents dir (pull via
    /// `xcrun simctl get_app_container <udid> de.plontsch.Steps data`).
    static func renderAll() {
        write(FeatureGridSquare(), named: "feature-grid")
        write(FeatureActivitiesSquare(), named: "feature-activities")
        write(FeatureWalkSquare(), named: "feature-walk")
        write(FeatureWatchSquare(), named: "feature-watch")
    }

    private static func write<V: View>(_ view: V, named name: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3   // 640pt → 1920px, downscaled for the web later
        guard let image = renderer.uiImage, let data = image.pngData() else {
            print("FEATURE_SHOT_FAIL \(name)")
            return
        }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url)
            print("FEATURE_SHOT_WROTE \(url.path)")
        } catch {
            print("FEATURE_SHOT_FAIL \(name): \(error)")
        }
    }
}

// MARK: - Previews (square canvas)

#Preview("Feature · Grid") { FeatureGridSquare() }
#Preview("Feature · Activities") { FeatureActivitiesSquare() }
#Preview("Feature · Walk") { FeatureWalkSquare() }
#Preview("Feature · Watch") { FeatureWatchSquare() }
#endif
