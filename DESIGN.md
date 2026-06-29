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

**Complication family coverage.** Steps offers three lock-screen / watch-face widgets across every
accessory family:

| Widget | Families | Content |
|--------|----------|---------|
| **Steps Ring** | circular · rectangular · inline · **corner** (watchOS) | Goal-progress ring + today's count. Corner = compact count in the corner with a curved **progress `Gauge`** along the bezel. Rectangular adds the activity reward badges. |
| **Tiny Steps** | circular · rectangular · inline · **corner** (watchOS) | The per-1,000 stage glyph over a thin ring. Corner = stage glyph + curved bezel `Gauge`. Rectangular adds the activity reward badges. |
| **Steps Grid** | rectangular (watchOS **and** iOS lock screen) | A compact GitHub-style contribution grid, weeks-as-columns. |

`.accessoryCorner` is watchOS-only, so its `supportedFamilies` entry and view branches are wrapped in
`#if os(watchOS)` (the view/widget files are shared with the iOS target). `StepsGridComplication.swift`
holds the grid complication's entry, provider, view, and widget — shared by both bundles.

**Accessory tinting → opacity, not hue.** Accessory complications are rendered monochrome / vibrant
by the system, which flattens the OKLCH ramp. So the grid complication encodes each day's intensity
via **cell opacity** (`Color.primary` at ~0.12→1.0 of the goal fraction) rather than colour — the tint
preserves opacity as brightness, keeping the contribution-graph feel. Today's cell gets a `.primary`
ring. The same **activity reward badges** (cycling / strength / mindful) appear only in the roomy
families — rectangular and the grid — where there's space; circular / corner / inline omit them.

## Notifications — the encouragement system

All local notifications are opt-in behind one **"Milestone alerts"** toggle (Settings sheet →
`SettingsStore.notificationsEnabledKey`). When on, the app requests `.alert + .sound` once; later
toggles are silent. Every alert carries the same custom chime (`StepsChime.wav`) and is posted
immediately (`trigger: nil`).

**How they fire.** There is no scheduling. `HealthKitService`'s long-lived step observer wakes the
app (foreground *or* background — throttled to ~hourly when closed) on every new step sample, passes
today's running total to `StepNotifier.shared.evaluate(todaySteps:)`, and the notifier decides what,
if anything, is due. Because background delivery is bursty and "catch-up" by nature, every state is
guarded so it fires **at most once per day** and resets at the local start-of-day. `evaluate` no-ops
entirely when the toggle is off.

**Per-day guards** (all in `SettingsStore`, stored in the App Group, compared against
start-of-day epochs):

- `lastNotifiedThousand` — highest 1,000-step rung already announced today; reads as `0` on a new day.
- `hasFiredToday(key)` / `markFiredToday(key)` — generic once-a-day latch (`morning`, `finalPush`, `doubleGoal`, `streak`, `record`).
- `hasNotifiedMonthRecordToday` / `markMonthRecordNotifiedToday` — monthly-best latch; resets daily, while the record itself resets monthly (only current-month days are compared).

### States

Evaluated in this order each refresh; states are independent (distinct notification ids) except
where noted under **Precedence**.

| State | Trigger | Guard (once/day) | Copy |
|-------|---------|------------------|------|
| **Morning greeting** | First steps land **and** local hour < 12 | `morning` | 🌅 "First steps" · "Good morning — you're moving!" |
| **Milestone ladder** | Crossing each new 1,000-step rung (1k…9k), capped at the goal | `lastNotifiedThousand` (climbs through the day) | `<emoji> 6,000 steps` · the stage's message (`stage(for:)`) |
| **Goal reached** | Crossing 10,000 (the 10th rung) | same ladder guard | 🏆 "Goal reached!" · "Goal reached! Amazing." |
| **Final push** | Local hour **≥ 18** **and** goal within reach: `0 < (goal − steps) < 1,000` (i.e. below goal) | `finalPush` | 🤏 "So close!" · "Just 700 steps to your 10,000-step goal — you're this close." |
| **Double goal** | `steps ≥ goal × 2` (20,000) | `doubleGoal` | 💪 "Double goal!" · "20,000 steps — twice your goal today." |
| **Goal streak** | Goal hit today **and** consecutive goal-days ∈ {3, 7, 14, 30} (walked back through the cache) | `streak` | 🔥 "7-day streak!" · "7 days at goal in a row. Keep it going!" |
| **Record day** | Today beats the best **other** day in the cached ~6-week window (`best > 0`) | `record` | 🏆 "Record day!" · "your best in weeks!" |
| **Monthly best** | Today beats the best **other** current-month day (`priorBest > 0`) | monthly-best latch | 🏅 "New monthly best!" · "your biggest day this month." |

**Precedence.** A **Record day** suppresses the lesser **Monthly best** the same day (it sets the
monthly-best latch too), so a single day yields one "best" alert, not both. The **Final push** is
mutually exclusive with **Goal reached** by construction (it only fires *below* goal); it can still
coincide with the 9,000 milestone if that rung is first crossed after 18:00, by design — one is a
neutral progress mark, the other an evening "last lap" nudge.

**Edge cases & resets.** A fresh day resets every guard, so the full ladder and the fun moments are
available again. The DEBUG "Simulate +1,000 steps" action zeroes `lastNotifiedThousand` so the ladder
can be replayed. Streak/record reads come from the App Group cache, which is refreshed immediately
before `evaluate` runs, so "prior best" always excludes today by construction.
