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
| Accent | gold `#F5A623` | `AccentColor.colorset` | Steps fingerprint; kept (not notes-plontsch lavender) and == grid goal colour. |
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

| Token | Value | Source | Why |
|-------|-------|--------|-----|
| Grid ramp | `#9be9a8 → #40c463 → #30a14e → #216e39` (L1–L4) over empty `#EDEDF0` | `StepsGridView.swift` | GitHub-style contribution data — load-bearing, not chrome. |
| Goal-reached | `#F5A623` gold (L5, 10000+) | `StepsGridView.swift` | A goal-hit day must stand out from the darkest green. |
| Today | `Color.primary` ring on today's cell | `StepsGridView.swift` | Find today at a glance against any fill. |
| Goal | `10000` (fixed) | `HealthKitService.swift` | A colour should mean the same thing every day. |
