# Steps project page design

## Project identity

Steps is a personal iOS, widget, and watchOS experience that turns Apple Health step data into a
month-shaped contribution grid, then suggests a real walk when today's total is short of 10,000.

Audience: people who want a glanceable, personal step history without turning walking into a
competitive fitness dashboard.

## App icon source and treatment

The Website uses the real Steps icon at `docs/blog/img/icon.png`, rendered from the project's Icon
Composer source. Its glass treatment and transparent corners are baked into the asset.

Keep shared icon boxes unclipped and unrounded in CSS. The icon artwork itself remains project-owned.

## Accent, palette, and type

The Website uses the family light/dark bases with a project-owned pink/rose accent pair: bright pink
`#FF5184` in light appearance and rose `#f38ba8` in dark appearance.

## Family contract

Family contract version applied: `2026-07-14.19`.

Local family decisions:

- Preserve the pink/rose accent pair, product icon, hero copy, and real product screenshots.
- Preserve the interactive phone and watch cascades.
- Preserve the four-card feature grid and its order: Suggested walk, Badges, Colors, Watch.
- Keep the feature grid visually headingless; name it accessibly in markup.
- Keep the compact home-page changelog visually headingless; name it accessibly in markup.
- Keep the three newest changelog entries as single-line links on the home page, followed by one
  link to the complete changelog.

## Hero story and media rationale

The hero opens with the practical promise of a suggested walk that closes today's step gap, then
briefly names badges, the grid, and the watch app.

Its three real screenshots show the product across its main surfaces:

- `img/shot-home-widget.png`: the placed home-screen widget.
- `img/shot-inapp.png`: the in-app total, badges, and suggestion.
- `img/shot-flyover.png`: the 3D route flyover.

The horizontal phone cascade keeps all three states visible while letting tap, keyboard, or
motion-safe autoplay change which state leads.

## Section hierarchy

- Global family header: Notes, About, and the Louder/Steps project icon strip.
- Hero: icon, product promise, primary Download and Build action, and phone screenshots.
- Feature grid: Suggested walk, Badges, Colors, and Watch.
- Changelog: three recent single-line links, followed by the full-log link.
- Footer: project provenance and author credit.

## Screenshot inventory and capture notes

- `img/shot-home-widget.png`
- `img/shot-inapp.png`
- `img/shot-flyover.png`
- `img/feature-walk.png`
- `img/feature-activities.png`
- `img/feature-grid.png`
- `img/watch-app.png`
- `img/watch-history.png`

Feature tiles are real SwiftUI view renders. Phone and watch images are real simulator captures. If a
tile needs a different composition, change the DEBUG renderer or reachable app state and recapture it
rather than editing product UI out of the pixels.

## Decisions made by project-site-family-apply

### 2026-07-14

- Created this identity record before applying broad family changes.
- Applied the canonical sticky global header to the home page and changelog.
- Removed the generic Get in touch hero action because the global header now owns About.
- Normalized shared icon, title, section-heading, changelog-title, and action-control metrics.
- Added accessible section naming, skip navigation, reduced-motion behavior, and focus-safe cascades.
- Repeated the newest changelog entry on the home page before the full-log link.
- Preserved all project-owned copy, screenshots, feature order, accent, palette, and custom media
  composition.
- Replaced the repeated full changelog article with three recent single-line links while keeping
  every full entry on `changelog.html`.
- Applied the non-sticky split family header, appearance controls, local family assets, and
  borderless hero media from contract `2026-07-14.18`.
- Moved body width and responsive horizontal insets into the canonical family shell so Notes and
  Steps retain the same content column at every viewport width.
