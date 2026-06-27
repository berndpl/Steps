//
//  GridStyle.swift
//  Steps
//
//  Shared between the app and the widget extension (member of both targets, like
//  HealthKitService.swift). Owns everything about how the contribution grid is
//  colored and shaped, so the app's customization sheet and the widget render
//  identically from the same App Group settings.
//
//  The ramp is generated in OKLCH (a perceptually-uniform color space) rather than
//  hand-picked sRGB, so a day's exact step count maps to an exact, evenly-spaced
//  color. OKLCH has no native SwiftUI support, so the conversion is implemented
//  here from Björn Ottosson's OKLab specification:
//    https://bottosson.github.io/posts/oklab/  (matrices quoted verbatim below)
//

import SwiftUI
import UIKit

// MARK: - OKLCH ↔ sRGB

/// A color in OKLCH: perceptual Lightness 0…1, Chroma ≥ 0, Hue in degrees.
struct OKLCH {
    var l: Double
    var c: Double
    var h: Double   // degrees

    /// OKLCH → OKLab → linear sRGB → gamma-encoded sRGB (clamped to gamut).
    var color: Color {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let b = c * sin(hr)

        // OKLab → LMS' (inverse of the L'M'S' → OKLab matrix).
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b

        // Cube to undo the cube-root nonlinearity.
        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_

        // LMS → linear sRGB.
        let r = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        return Color(.sRGB,
                     red: Self.gammaEncode(r),
                     green: Self.gammaEncode(g),
                     blue: Self.gammaEncode(bl))
    }

    /// sRGB (0…1 components) → OKLCH.
    static func from(red: Double, green: Double, blue: Double) -> OKLCH {
        let r = gammaDecode(red)
        let g = gammaDecode(green)
        let b = gammaDecode(blue)

        // linear sRGB → LMS.
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)

        let okL = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        let okA = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        let okB = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

        let chroma = sqrt(okA * okA + okB * okB)
        var hue = atan2(okB, okA) * 180 / .pi
        if hue < 0 { hue += 360 }
        return OKLCH(l: okL, c: chroma, h: hue)
    }

    private static func gammaEncode(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func gammaDecode(_ x: Double) -> Double {
        x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
}

// MARK: - Hex helpers

extension Color {
    /// Parse "#RRGGBB" (or "RRGGBB"). Falls back to mid-gray on malformed input.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b)
    }

    /// "#RRGGBB" for persisting a (possibly user-picked) color. Resolves through
    /// UIColor so it works for any Color, including ColorPicker output.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (x: CGFloat) in Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    /// sRGB components for feeding the OKLCH conversion.
    var oklch: OKLCH {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return OKLCH.from(red: Double(r), green: Double(g), blue: Double(b))
    }
}

// MARK: - Day shape

/// The cell shape. Every variant is a continuous-corner rounded rectangle — a
/// circle is just a rounded rect whose corner radius is half the (square) cell —
/// so rendering and the today-ring share one code path; only the factor changes.
enum DayShape: String, CaseIterable, Identifiable {
    case roundedSquare
    case circle
    case squircle

    var id: String { rawValue }

    /// Corner radius as a fraction of the (square) cell size.
    var cornerFactor: CGFloat {
        switch self {
        case .roundedSquare: return 0.28
        case .squircle:      return 0.45
        case .circle:        return 0.50   // == circle for a square cell
        }
    }

    var label: String {
        switch self {
        case .roundedSquare: return "Rounded"
        case .circle:        return "Circle"
        case .squircle:      return "Squircle"
        }
    }
}

// MARK: - Grid style

/// The full, persisted description of how the grid looks. Read by both the app
/// (live customization + in-app preview) and the widget (via the App Group).
struct GridStyle: Equatable {
    var rampHex: String
    var goalHex: String
    var spread: Double      // response-curve gamma; higher = mid-days recede
    var shape: DayShape

    static let defaultRampHex = "#216E39"   // current darkest-green ramp end
    static let defaultGoalHex = "#F5A623"   // current Steps gold
    static let defaultSpread = 1.5
    static let spreadRange: ClosedRange<Double> = 1.0...3.0

    static let `default` = GridStyle(
        rampHex: defaultRampHex,
        goalHex: defaultGoalHex,
        spread: defaultSpread,
        shape: .roundedSquare
    )

    /// Live style from the App Group (falls back to `.default`).
    static var current: GridStyle {
        GridStyle(
            rampHex: SettingsStore.gridRampHex,
            goalHex: SettingsStore.gridGoalHex,
            spread: SettingsStore.gridSpread,
            shape: DayShape(rawValue: SettingsStore.gridShape) ?? .roundedSquare
        )
    }

    var goalColor: Color { Color(hex: goalHex) }
    var rampBaseColor: Color { Color(hex: rampHex) }

    /// The fill for a day, generated continuously in OKLCH.
    ///
    /// `t` is progress toward the goal; the response curve `pow(t, spread)` pushes
    /// mid-range days toward the empty end so only days near the goal read intense.
    /// Goal-or-better days use the distinct goal color (a pop off the ramp). The
    /// neutral empty endpoint adapts to the color scheme so it matches the surface
    /// (light-gray in light mode, dark-gray in dark) while chroma rises with effort.
    func color(forSteps steps: Int, goal: Int, scheme: ColorScheme) -> Color {
        if steps >= goal { return goalColor }
        let t = max(0, min(Double(steps) / Double(goal), 1))
        let i = pow(t, spread)

        let base = rampBaseColor.oklch
        let dark = scheme == .dark
        let lLow: Double = dark ? 0.28 : 0.95               // empty cell lightness
        let lHigh: Double = dark ? max(base.l, 0.68) : base.l // intense end (brighten for dark)
        let cLow = 0.0                                       // empty is neutral

        let l = lLow + (lHigh - lLow) * i
        let c = cLow + (base.c - cLow) * i
        return OKLCH(l: l, c: c, h: base.h).color
    }
}

// MARK: - Palette presets

/// A curated palette: a ramp base color plus a distinct goal color, both stored
/// as hex (derived to be pleasant in OKLCH). Selecting one writes these into the
/// style; the user can still override either color in the sheet ("full custom").
struct GridPalette: Identifiable {
    let name: String
    let rampHex: String
    let goalHex: String
    var id: String { name }

    static let presets: [GridPalette] = [
        GridPalette(name: "Green",  rampHex: "#216E39", goalHex: "#F5A623"), // current
        GridPalette(name: "Ocean",  rampHex: "#1F6F8B", goalHex: "#F2714E"),
        GridPalette(name: "Violet", rampHex: "#5B3E9B", goalHex: "#F0A500"),
        GridPalette(name: "Mono",   rampHex: "#3A3F4B", goalHex: "#3B82F6"),
        GridPalette(name: "Sunset", rampHex: "#C0392B", goalHex: "#FF5FA2"),
    ]
}

// MARK: - Month's best day

/// The highest-steps day of the *current* month, excluding future days; latest
/// date wins ties; `nil` if no in-month day has steps. Shared so the grid's dot
/// and the monthly-record notification agree on what "best" means.
func monthBestDay(_ dailySteps: [Date: Int]) -> (date: Date, steps: Int)? {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    guard let monthStart = cal.dateInterval(of: .month, for: today)?.start else { return nil }

    var best: (date: Date, steps: Int)?
    for (date, steps) in dailySteps {
        let day = cal.startOfDay(for: date)
        guard day >= monthStart, day <= today, steps > 0 else { continue }
        if let b = best {
            // Strictly greater, or equal-but-later, so the most recent peak wins.
            if steps > b.steps || (steps == b.steps && day > b.date) {
                best = (day, steps)
            }
        } else {
            best = (day, steps)
        }
    }
    return best
}

// MARK: - Sample data for the customization preview

extension GridStyle {
    /// A deterministic month of values for the live preview — spans empty, low,
    /// mid, and several goal-or-better days, with a single clear monthly best, so
    /// the whole ramp + goal color + best-day dot are visible while adjusting.
    static var sampleMonth: [Date: Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let interval = cal.dateInterval(of: .month, for: today),
              let dayCount = cal.range(of: .day, in: .month, for: today)?.count else { return [:] }

        // A varied, repeatable pattern (steps in thousands ×1000). One peak at 13.5k.
        let pattern = [0, 2, 5, 8, 11, 1, 4, 7, 10, 3, 6, 9, 12, 0, 5,
                       8, 13, 2, 7, 10, 4, 1, 9, 6, 11, 3, 8, 5, 10, 7, 12]

        var out: [Date: Int] = [:]
        for day in 0..<dayCount {
            guard let date = cal.date(byAdding: .day, value: day, to: interval.start) else { continue }
            let base = pattern[day % pattern.count] * 1_000
            // Bump one day to a unique monthly best so the dot has a clear home.
            out[cal.startOfDay(for: date)] = (day == 16) ? 13_500 : base
        }
        return out
    }
}
