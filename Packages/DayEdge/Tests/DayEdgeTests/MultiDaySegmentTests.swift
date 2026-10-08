import XCTest
@testable import Shell
@testable import UI

final class MultiDaySegmentTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func day(_ day: Int) -> Date {
        date(day, 0)
    }

    // TEST A — 22 Sep 15:45 -> 22 Sep 16:45
    func testSameDayEvent() {
        XCTAssertEqual(
            MultiDaySegment.classify(start: date(22, 15, 45), end: date(22, 16, 45), day: day(22), calendar: calendar),
            .sameDay
        )
    }

    // TEST B — 22 Sep 15:45 -> 23 Sep 16:45
    func testStartsTodayEndsTomorrow() {
        let start = date(22, 15, 45)
        let end = date(23, 16, 45)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(22), calendar: calendar), .startsHereEndsLater)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(23), calendar: calendar), .endsHere)
    }

    // TEST C — 22 Sep 23:30 -> 23 Sep 00:30
    func testShortOvernightEvent() {
        let start = date(22, 23, 30)
        let end = date(23, 0, 30)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(22), calendar: calendar), .startsHereEndsLater)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(23), calendar: calendar), .endsHere)
    }

    // TEST D — Mon 22 Sep 15:45 -> Thu 25 Sep 16:45
    func testEventSpanningFourDays() {
        let start = date(22, 15, 45)
        let end = date(25, 16, 45)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(22), calendar: calendar), .startsHereEndsLater)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(23), calendar: calendar), .continuesThroughDay)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(24), calendar: calendar), .continuesThroughDay)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(25), calendar: calendar), .endsHere)
    }

    // TEST E — 22 Sep 15:00 -> 23 Sep 00:00 (exclusive midnight end)
    func testEndingExactlyAtMidnightDoesNotOccupyTheNextDay() {
        let start = date(22, 15, 0)
        let end = date(23, 0, 0)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(22), calendar: calendar), .sameDay)
        XCTAssertNil(MultiDaySegment.classify(start: start, end: end, day: day(23), calendar: calendar))
    }

    // TEST G — event started before the visible/queried range
    func testDayInTheMiddleOfALongerSpanStillClassifiesWithoutSeeingTheStartDay() {
        let start = date(20, 12, 0)
        let end = date(23, 16, 0)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(22), calendar: calendar), .continuesThroughDay)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: day(23), calendar: calendar), .endsHere)
    }

    func testDayNotTouchedByTheEventReturnsNil() {
        let start = date(22, 15, 0)
        let end = date(22, 16, 0)
        XCTAssertNil(MultiDaySegment.classify(start: start, end: end, day: day(23), calendar: calendar))
        XCTAssertNil(MultiDaySegment.classify(start: start, end: end, day: day(21), calendar: calendar))
    }

    func testDaylightSavingTransitionDayStillClassifiesByCalendarDate() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        // Spring-forward 2026-03-08 in America/Los_Angeles is a 23-hour day.
        let start = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 0)))
        let end = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 3, minute: 0)))
        let dstDay = losAngeles.startOfDay(for: start)
        let nextDay = try XCTUnwrap(losAngeles.date(byAdding: .day, value: 1, to: dstDay))

        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: dstDay, calendar: losAngeles), .startsHereEndsLater)
        XCTAssertEqual(MultiDaySegment.classify(start: start, end: end, day: nextDay, calendar: losAngeles), .endsHere)
    }
}
