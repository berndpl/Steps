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

struct StepsGridView: View {
    /// Per-day step totals keyed by local start-of-day (from HealthKitService).
    let dailySteps: [Date: Int]

    private let columns = 7   // days of the week

    /// GitHub-inspired green ramp, level 0...4. Comment keeps values regenerable.
    /// Buckets are quarters of the 10k goal (see `level(for:)`):
    ///   L0 empty, L1 #9be9a8, L2 #40c463, L3 #30a14e, L4 #216e39.
    private let ramp: [Color] = [
        Color(.sRGB, red: 0.93, green: 0.93, blue: 0.94),       // L0 empty (in-month, 0 steps)
        Color(.sRGB, red: 0.61, green: 0.91, blue: 0.66),       // L1
        Color(.sRGB, red: 0.25, green: 0.77, blue: 0.39),       // L2
        Color(.sRGB, red: 0.19, green: 0.63, blue: 0.31),       // L3
        Color(.sRGB, red: 0.13, green: 0.43, blue: 0.22),       // L4
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
            if date > today {
                // Future days this month: faint placeholder.
                RoundedRectangle(cornerRadius: corner)
                    .fill(ramp[0].opacity(0.4))
            } else {
                let steps = dailySteps[date] ?? 0
                RoundedRectangle(cornerRadius: corner)
                    .fill(ramp[level(for: steps)])
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
