# Design Choices

Per-target style, distinct **gold** accent across both. Applied via `style-apply`.
Each token: **value → source → why**. Local *data* directives (the contribution
grid) always win.

- **App** → `notes-plontsch` (Bernd's personal default) adapted to SwiftUI — updated 2026-06-25.
- **Widget** → the `Spark`/Letters widget family — applied 2026-06-25.

Catalog: `Steps` (`projects/Steps/Steps.tokens.json`).

## App — notes-plontsch (Catppuccin, monospaced, flat)

| Token | Value | Source | Why |
|-------|-------|--------|-----|
| Background | Catppuccin **Mocha `#1e1e2e`** (dark) / **Latte `#f7f8fb`** (light) | `AppBackground.colorset` | notes-plontsch base; emitted as a light+dark colorset (opt-in light/dark). |
| Text primary | `#cdd6f4` / `#363a4f` | `AppText.colorset` | Catppuccin text. |
| Text muted | `#6c7086` / `#9498ab` | `AppTextMuted.colorset` | Catppuccin overlay0 — "steps today", body, denied copy, debug glyph. |
| Font | `.system(design: .monospaced)` (SF Mono) | `ContentView.swift` | notes-plontsch is Inconsolata mono throughout; SF Mono is the owner-chosen stand-in. |
| Weight | medium / regular (flattened) | `ContentView.swift` | notes-plontsch forces 400 — emphasis from size + colour, not weight (taste C1). |
| Number | 68pt medium monospaced, gold | `ContentView.swift` `stepsView` | The one hero; colour (gold) + size carry it, not boldness. |
| Accent | gold `#F5A623` default, now == the **palette goal colour** (`.tint`) | `ContentView.swift` / `AccentColor.colorset` | Steps fingerprint; follows the customizer's goal colour so app + grid cohere. |
| Shadows | none | `ContentView.swift` | Flat; depth via Catppuccin surface tints. |
| CTA | `.glassProminent` | `ContentView.swift` | Deskgym remnant — the single deliberate action stays Liquid Glass. |
| Count motion | `spring(0.28, 0.86)` + `.numericText()` | `ContentView.swift` | Deskgym remnant — smooth count. |
| Debug affordance | single `ladybug.fill` Menu, top-trailing (DEBUG) | `ContentView.swift` `debugMenu` | Replaced the bottom chip toolbar with one button. |

## Widget — Spark/Letters family (overrides the app style on the widget target)

| Token | Value | Source | Why |
|-------|-------|--------|-----|
| Background | `.containerBackground(.clear)` + faint black scrim (`0.02` + `0.05→0.02`) | `StepsWidget.swift` | Spark/Letters: quiet, near-transparent — no solid fill. |
| Clip | `ContainerRelativeShape` | `StepsWidget.swift` | Follows the system widget shape. |
| Insets | `18pt` + `.contentMarginsDisabled()` | `StepsWidget.swift` | Spark/Letters `LayoutMetrics`. |
| Today's count | `.system(.footnote, design:.monospaced, weight:.semibold)`, gold, leading | `StepsGridView.swift` | Just the number — no glyph/label (owner request). |
| Deep-link | `widgetURL("steps://open")` | `StepsWidget.swift` | Tap opens the app (like Letters `letters://open`). |

## Local directives (win over both styles) — the contribution grid

The grid is now **generated in OKLCH** (perceptually-uniform), not hand-picked sRGB, and is
**user-customizable** (palette, spread, shape) via the paintbrush sheet. Values persist to the
App Group so the widget renders identically. OKLCH math: `GridStyle.swift` (Björn Ottosson).

| Token | Value | Source | Why |
|-------|-------|--------|-----|
| Grid fill | **continuous** OKLCH ramp: neutral empty → `rampBase` (default `#216E39`), chroma rising with effort | `GridStyle.color(forSteps:)` | A day's exact steps → an exact, evenly-spaced colour — more spread than 5 buckets. |
| Curve | a `CurveShape` (linear / ease-in / ease-out / ease-in-out / log / exp) + `strength` 0–1 (default ease-in, 0.5) | `CurveShape.apply` | Pick *how* steps map to fill intensity; previewed as a sparkline in the sheet. |
| Goal-reached | distinct **goal colour** per palette (default gold `#F5A623`), 10000+ | `GridStyle.color(forSteps:)` | A goal-hit day must pop off the ramp's most-intense step. |
| Empty endpoint | neutral, **adapts to scheme** (light-gray / dark-gray) | `GridStyle.color(forSteps:)` | Matches the surface in both modes; background stays neutral. |
| Today | **luminous** goal colour (OKLCH lightness+chroma boosted), stroked **outside** the cell | `GridStyle.todayRingColor`, `StepsGridView.swift` | Out-pops every fill incl. a goal-day; the full fill stays visible. |
| Month's best | a chosen **marker** — dot (default) / ring / asterisk / star / none — auto black-or-white by cell OKLCH lightness | `BestDayMarker`, `StepsGridView.swift` | Mark the month's peak day subtly, readable on any fill, without echoing today's ring. |
| Day shape | `roundedSquare` (default) / `circle` / `squircle` — one rounded-rect path, corner factor only | `DayShape` | Customizable cell shape; circle = corner 0.5 of a square cell. |
| Palettes | 12 curated presets (Green/Ocean/Violet/Mono/Sunset/Teal/Indigo/Rose/Amber/Slate/Crimson/Forest) + full custom (ramp + goal wells) | `GridPalette.presets` | Designed in OKLCH; user can override either colour. |
| Activity badges | today's logged cycling / meditation / strength as `figure.outdoor.cycle.circle.fill` · `figure.mind.and.body.circle.fill` · `figure.strengthtraining.traditional.circle.fill`, tinted goal colour | `DayActivity`, `StepsMonthView` | A glanceable "what else I did today" beside the count. |
| Accent ripple | palette **goal colour** becomes the app `.tint` (hero number, CTA, today ring) | `ContentView.swift` | Grid + app cohere; **background colorsets untouched**. |
| Goal | `10000` (fixed) | `HealthKitService.swift` | A colour should mean the same thing every day; keeps the per-1,000 stage mapping clean. |

**Watch complications** reuse the same `StepsRingView` / `TinyStepsView` accessory views (via the
shared `StepsAccessoryWidgets.swift`); the watch reads HealthKit directly (no App Group sync across
devices). Notifications carry a custom bundled chime (`StepsChime.wav`).
