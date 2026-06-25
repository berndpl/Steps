//
//  StepsGridView.swift
//  StepsWidget
//
//  Calendar-month grid: laid out like a normal month calendar — 7 weekday
//  columns across, week rows down. The current month's days sit in their real
//  weekday positions; leading/trailing days outside the month are blank.
//  Each in-month day's color intensity is bucketed against the daily step goal.
//

import SwiftUI

extension Color {
    /// Steps accent / goal-reached gold (#F5A623). Shared by app + widget.
    static let stepsGold = Color(.sRGB, red: 0.96, green: 0.65, blue: 0.14)
}

/// The full small-widget content: the calendar-month grid plus today's step
/// count. Shared so the widget and the in-app preview render identically.
struct StepsMonthView: View {
    let dailySteps: [Date: Int]

    private var todaySteps: Int {
        dailySteps[Calendar.current.startOfDay(for: Date())] ?? 0
    }

    var body: some View {
        VStack(spacing: 6) {
            StepsGridView(dailySteps: dailySteps)
            // Today's count — just the number (Spark/Letters: monospaced).
            Text(todaySteps, format: .number)
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(Color.stepsGold)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StepsGridView: View {
    /// Per-day step totals keyed by local start-of-day (from HealthKitService).
    let dailySteps: [Date: Int]

    private let columns = 7   // days of the week

    /// GitHub-inspired green ramp (L0–L4) plus a standout gold for goal-reached
    /// days (L5). Comment keeps values regenerable. See `level(for:)`:
    ///   L0 empty, L1 #9be9a8, L2 #40c463, L3 #30a14e, L4 #216e39,
    ///   L5 goal reached → #F5A623 (gold, pops against the green).
    private let ramp: [Color] = [
        Color(.sRGB, red: 0.93, green: 0.93, blue: 0.94),       // L0 empty (in-month, 0 steps)
        Color(.sRGB, red: 0.61, green: 0.91, blue: 0.66),       // L1
        Color(.sRGB, red: 0.25, green: 0.77, blue: 0.39),       // L2
        Color(.sRGB, red: 0.19, green: 0.63, blue: 0.31),       // L3
        Color(.sRGB, red: 0.13, green: 0.43, blue: 0.22),       // L4
        .stepsGold,                                             // L5 goal reached (gold)
    ]

    var body: some View {
        let month = MonthLayout()

        GeometryReader { geo in
            let spacing = geo.size.width * 0.04
            let cellW = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellH = (geo.size.height - spacing * CGFloat(month.rows - 1)) / CGFloat(month.rows)
            let cell = max(min(cellW, cellH), 1)
            let corner = cell * 0.28

            VStack(spacing: spacing) {
                ForEach(0..<month.rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { col in
                            cellView(index: row * columns + col, month: month, corner: corner)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func cellView(index: Int, month: MonthLayout, corner: CGFloat) -> some View {
        let dayNumber = index - month.leadingBlanks + 1

        if dayNumber < 1 || dayNumber > month.dayCount {
            // Outside the current month: blank so the month's shape reads clearly.
            Color.clear
        } else if let date = month.date(forDay: dayNumber) {
            let today = Calendar.current.startOfDay(for: Date())
            let fill = date > today ? ramp[0].opacity(0.4)          // future day, faint
                                    : ramp[level(for: dailySteps[date] ?? 0)]
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(fill)
                .overlay {
                    if date == today {
                        // Highlight today with a gold ring (Steps accent).
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.stepsGold, lineWidth: max(corner * 0.45, 1.3))
                    }
                }
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
