//
//  StepsGridView.swift
//  StepsWidget
//
//  Calendar-month grid: laid out like a normal month calendar — 7 weekday
//  columns across, week rows down. The current month's days sit in their real
//  weekday positions; leading/trailing days outside the month are blank.
//  Each in-month day's color is generated continuously in OKLCH from the user's
//  chosen GridStyle (palette, spread/response-curve, goal color), and the cell
//  shape follows the chosen DayShape. See GridStyle.swift.
//

import SwiftUI

extension Color {
    /// Steps accent / goal-reached gold (#F5A623). Retained as the brand default
    /// even though the grid now reads its goal color from `GridStyle`.
    static let stepsGold = Color(.sRGB, red: 0.96, green: 0.65, blue: 0.14)
}

/// The full small-widget content: the calendar-month grid plus today's step
/// count. Shared so the widget and the in-app preview render identically. A
/// `style` can be injected so the customization sheet can preview a live draft.
struct StepsMonthView: View {
    let dailySteps: [Date: Int]
    var style: GridStyle = .current
    /// Activities done today, shown as small badges beside the count.
    var activities: Set<DayActivity> = []

    private var todaySteps: Int {
        dailySteps[Calendar.current.startOfDay(for: Date())] ?? 0
    }

    var body: some View {
        VStack(spacing: 6) {
            StepsGridView(dailySteps: dailySteps, style: style)
            // Today's count — just the number (Spark/Letters: monospaced), tinted
            // with the palette's goal color — plus today's activity badges trailing.
            HStack(spacing: 4) {
                Text(todaySteps, format: .number)
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(style.goalColor)
                Spacer(minLength: 4)
                ForEach(DayActivity.allCases.filter(activities.contains)) { activity in
                    Image(systemName: activity.symbol)
                        .font(.footnote)
                        .foregroundStyle(style.goalColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The medium-widget layout: a square month grid beside a stats panel (today's
/// stage glyph + count + goal, activity badges, and the month's best day).
/// Shared so the iOS `.systemMedium` widget and the watch app render identically.
struct StepsMediumView: View {
    let dailySteps: [Date: Int]
    var style: GridStyle = .current
    var activities: Set<DayActivity> = []

    private var todaySteps: Int {
        dailySteps[Calendar.current.startOfDay(for: Date())] ?? 0
    }

    var body: some View {
        HStack(spacing: 16) {
            StepsGridView(dailySteps: dailySteps, style: style)
                .aspectRatio(1, contentMode: .fit)
            statsPanel
            Spacer(minLength: 0)
        }
    }

    private var statsPanel: some View {
        let stage = stage(for: todaySteps)
        let best = monthBestDay(dailySteps)
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: stage.symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(style.goalColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(todaySteps, format: .number)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(style.goalColor)
                Text("of \(dailyStepGoal.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !activities.isEmpty {
                HStack(spacing: 4) {
                    ForEach(DayActivity.allCases.filter(activities.contains)) { activity in
                        Image(systemName: activity.symbol)
                            .font(.footnote)
                            .foregroundStyle(style.goalColor)
                    }
                }
            }
            Spacer(minLength: 0)
            if let best {
                Text("Best \(best.steps.formatted())")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StepsGridView: View {
    /// Per-day step totals keyed by local start-of-day (from HealthKitService).
    let dailySteps: [Date: Int]
    var style: GridStyle = .current

    @Environment(\.colorScheme) private var scheme

    private let columns = 7   // days of the week

    var body: some View {
        let month = MonthLayout()
        let bestDay = monthBestDay(dailySteps)?.date

        GeometryReader { geo in
            let spacing = geo.size.width * 0.04
            let cellW = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellH = (geo.size.height - spacing * CGFloat(month.rows - 1)) / CGFloat(month.rows)
            let cell = max(min(cellW, cellH), 1)
            let corner = cell * style.shape.cornerFactor

            VStack(spacing: spacing) {
                ForEach(0..<month.rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { col in
                            cellView(index: row * columns + col, month: month,
                                     corner: corner, cell: cell, bestDay: bestDay)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func cellView(index: Int, month: MonthLayout, corner: CGFloat,
                          cell: CGFloat, bestDay: Date?) -> some View {
        let dayNumber = index - month.leadingBlanks + 1

        if dayNumber < 1 || dayNumber > month.dayCount {
            // Outside the current month: blank so the month's shape reads clearly.
            Color.clear
        } else if let date = month.date(forDay: dayNumber) {
            let today = Calendar.current.startOfDay(for: Date())
            let steps = dailySteps[date] ?? 0
            let fill: Color = date > today
                ? style.color(forSteps: 0, goal: dailyStepGoal, scheme: scheme).opacity(0.4) // future, faint
                : style.color(forSteps: steps, goal: dailyStepGoal, scheme: scheme)

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(fill)
                .overlay {
                    if date == bestDay {
                        // Subtle "month's best" marker. Pick black/white by the
                        // fill's OKLCH lightness so it stays recognizable on any color.
                        let ink: Color = fill.oklch.l < 0.55 ? .white.opacity(0.9)
                                                             : .black.opacity(0.55)
                        markerView(style.marker, cell: cell, ink: ink)
                    }
                }
                .overlay {
                    if date == today {
                        // Highlight today with a bright ring stroked *outside* the
                        // cell (in the gap), so the full fill stays visible and the
                        // ring never blends with a goal-day fill. Negative padding
                        // expands the rounded rect past the cell edge; the corner
                        // grows with it to stay concentric.
                        let lw = max(cell * 0.14, 2.0)
                        let outset = lw * 0.55
                        RoundedRectangle(cornerRadius: corner + outset, style: .continuous)
                            .stroke(style.todayRingColor, lineWidth: lw)
                            .padding(-outset)
                    }
                }
        }
    }

    /// The month's-best marker, sized to the cell and tinted for contrast.
    @ViewBuilder
    private func markerView(_ marker: BestDayMarker, cell: CGFloat, ink: Color) -> some View {
        switch marker {
        case .none:
            EmptyView()
        case .dot:
            Circle().fill(ink).frame(width: cell * 0.18, height: cell * 0.18)
        case .ring:
            Circle().strokeBorder(ink, lineWidth: max(cell * 0.06, 1))
                .frame(width: cell * 0.34, height: cell * 0.34)
        case .asterisk:
            Image(systemName: "asterisk")
                .font(.system(size: cell * 0.44, weight: .bold))
                .foregroundStyle(ink)
        case .star:
            Image(systemName: "star.fill")
                .font(.system(size: cell * 0.40))
                .foregroundStyle(ink)
        }
    }
}

/// Geometry of the current calendar month: how many leading blank cells precede
/// the 1st, how many days the month has, and how many week-rows it spans.
private struct MonthLayout {
    let calendar = Calendar.current
    let firstOfMonth: Date
    let leadingBlanks: Int
    let dayCount: Int
    let rows: Int

    init() {
        let cal = Calendar.current
        let today = Date()
        let start = cal.dateInterval(of: .month, for: today)?.start
            ?? cal.startOfDay(for: today)
        let days = cal.range(of: .day, in: .month, for: today)?.count ?? 30

        // Column offset of the 1st, honoring the user's first weekday (Sun/Mon).
        let weekday = cal.component(.weekday, from: start)
        let leading = (weekday - cal.firstWeekday + 7) % 7

        self.firstOfMonth = start
        self.dayCount = days
        self.leadingBlanks = leading
        self.rows = Int(ceil(Double(leading + days) / 7.0))
    }

    /// Local start-of-day for the given 1-based day of this month.
    func date(forDay day: Int) -> Date? {
        calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
            .map { calendar.startOfDay(for: $0) }
    }
}

#Preview("Month View") {
    StepsMonthView(dailySteps: HealthKitService.sampleDailySteps(),
                   activities: [.cycling, .strength])
        .padding(18)
        .frame(width: 170, height: 170)
}

#Preview("Grid Only") {
    StepsGridView(dailySteps: HealthKitService.sampleDailySteps())
        .padding(18)
        .frame(width: 170, height: 170)
}
