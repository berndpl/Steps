# Steps

Your last month of steps, as a GitHub-style contribution grid — a tiny iOS app
and home-screen widget that reads Apple Health and paints each day of the month
by how close you got to 10,000 steps.

📓 **[Devlog](https://berndpl.github.io/Steps/blog/)** — how it was built, post by post.

## What it does

- **App** — a single live view showing today's step count, with a clean Health
  permission flow (loading → permission → today's total → denied).
- **Visits & suggestions** — optional, opt-in visit tracking (Apple's low-power
  `CLVisit` dwell detection) logs the places you spend time at. A **History**
  sheet lists them with the round-trip walking cost home ↔ there (distance +
  estimated steps), and the main view nudges you with a line like *"A round trip
  to the café would get you there"* when it'd close today's gap to the goal.
- **Widget** — a small home-screen widget laying out the current calendar month
  like a real calendar: 7 weekday columns, week rows, the 1st in its true
  weekday slot (honoring Sunday/Monday week starts). Each past day is shaded
  against a fixed 10,000-step goal using GitHub's contribution ramp
  (`#9be9a8` → `#216e39`); future days fade, days outside the month stay blank.

The grid is a single `StepsGridView` shared between the app and the widget, so
the in-app preview and the home screen render from the exact same code.

## Build

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen      # if you don't have it
xcodegen generate          # regenerate Steps.xcodeproj from project.yml
open Steps.xcodeproj
```

Then set your own Apple Developer Team under **Signing & Capabilities** (the repo
ships with no team), select an iPhone simulator or device, and run.

Requirements: Xcode 26+, iOS 26.5+. The app requests **read-only** access to
step count via HealthKit. Step data stays on device; the visit-tracking feature
(opt-in) reaches Apple's map services only to compute walking distances
(MapKit) and reverse-geocode place names — no personal data is sent anywhere
else.

### Testing every screen

In `DEBUG` builds a bottom switcher (compiled out of release) lets you jump to
any state — including an in-app render of the widget grid with sample data — so
you can test without granting Health access or seeding data. You can also launch
straight into a state with `-STEPS_PREVIEW Grid` (Live · Permission · Loading ·
Steps · Denied · Grid). Pass `-STEPS_SEED_VISITS 1` to populate the visit log
with sample places (home + a couple of destinations) so History and the
round-trip suggestion are demonstrable without real `CLVisit` events; the
ladybug menu also has *Seed sample visits* / *Clear visits* actions.

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free to use, modify, and share for
**noncommercial** purposes only.
