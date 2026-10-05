import XCTest
@testable import Steps

final class Zone2ProgressTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testEstimatedRangeUsesHeartRateReserve() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 1
        )))
        let range = try XCTUnwrap(Zone2Calculator.estimatedRange(
            dateOfBirth: DateComponents(year: 1990, month: 1, day: 1),
            restingBPM: 60,
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(range, Zone2Range(lowerBPM: 134, upperBPM: 146))
    }

    func testMinutesCountInclusiveBoundsOnlyInsideWorkouts() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 10
        )))
        let week = DateInterval(start: start, duration: 60 * 60)
        let workouts = [
            DateInterval(start: start.addingTimeInterval(30), duration: 180),
            DateInterval(start: start.addingTimeInterval(120), duration: 180),
        ]
        let samples = [
            Zone2HeartRateSample(date: start.addingTimeInterval(35), bpm: 120),
            Zone2HeartRateSample(date: start.addingTimeInterval(65), bpm: 140),
            Zone2HeartRateSample(date: start.addingTimeInterval(125), bpm: 150),
            Zone2HeartRateSample(date: start.addingTimeInterval(305), bpm: 130),
        ]
        let range = try XCTUnwrap(Zone2Range(lowerBPM: 120, upperBPM: 140))

        XCTAssertEqual(
            Zone2Calculator.minutes(
                workoutIntervals: workouts,
                samples: samples,
                range: range,
                within: week,
                calendar: calendar
            ),
            2
        )
    }

    func testMissingSamplesAndSamplesOutsideWorkoutDoNotCount() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 10
        )))
        let range = try XCTUnwrap(Zone2Range(lowerBPM: 120, upperBPM: 140))

        XCTAssertEqual(Zone2Calculator.minutes(
            workoutIntervals: [DateInterval(start: start, duration: 60)],
            samples: [
                Zone2HeartRateSample(date: start.addingTimeInterval(90), bpm: 130)
            ],
            range: range,
            within: DateInterval(start: start, duration: 180),
            calendar: calendar
        ), 0)
    }

    func testWorkoutTimeOutsideTheCurrentWeekIsClipped() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 10
        )))
        let range = try XCTUnwrap(Zone2Range(lowerBPM: 120, upperBPM: 140))

        XCTAssertEqual(Zone2Calculator.minutes(
            workoutIntervals: [
                DateInterval(start: start.addingTimeInterval(-60), duration: 180)
            ],
            samples: [
                Zone2HeartRateSample(date: start.addingTimeInterval(-30), bpm: 130),
                Zone2HeartRateSample(date: start.addingTimeInterval(30), bpm: 130)
            ],
            range: range,
            within: DateInterval(start: start, duration: 60),
            calendar: calendar
        ), 1)
    }

    func testProgressCapsAtGoalWithoutDiscardingOverage() {
        let progress = WeeklyZone2Progress(minutes: 145)

        XCTAssertEqual(progress.minutes, 145)
        XCTAssertEqual(progress.cappedFraction, 1)
    }
}
