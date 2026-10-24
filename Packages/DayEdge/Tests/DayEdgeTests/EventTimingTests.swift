import XCTest
@testable import Domain
@testable import Intelligence

/// The rules both event editors share: a start and an end that are each a
/// date and a time, the end always after the start.
final class EventTimingTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()
    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func timed(_ start: Date, _ end: Date) -> EventTiming {
        EventTiming(start: start, end: end, isAllDay: false, calendar: calendar)
    }

    func testTheSameDayShowsThatDayTwice() {
        let timing = timed(at(18, 17), at(18, 18))
        XCTAssertEqual([timing.firstDay, timing.lastDay], [at(18), at(18)])
    }

    func testAnEndAtMidnightIsTheNextDay() {
        let timing = timed(at(18, 17), at(19, 0))
        XCTAssertEqual(timing.lastDay, at(19), "Ends: 19 Oct 00:00")
    }

    func testAnEndOnALaterDay() {
        let timing = timed(at(18, 23), at(19, 1, 30))
        XCTAssertEqual([timing.firstDay, timing.lastDay], [at(18), at(19)])
        XCTAssertEqual(timing.end, at(19, 1, 30))
    }

    func testAnEndNotAfterTheStartIsRepaired() {
        XCTAssertEqual(timed(at(18, 17), at(18, 17)).end, at(18, 18))
    }

    func testANewStartKeepsTheLength() {
        var timing = timed(at(18, 10), at(18, 11))
        timing.start = at(19, 14)
        XCTAssertEqual(timing.end, at(19, 15))
        timing.firstDay = at(21)
        XCTAssertEqual([timing.start, timing.end], [at(21, 14), at(21, 15)], "a new day keeps the clock time too")
    }

    func testAnEndTimeBeforeTheStartIsTheNextDay() {
        var timing = timed(at(18, 23), at(19, 0))
        timing.end = at(18, 1)
        XCTAssertEqual(timing.end, at(19, 1))
    }

    func testAnEndDayKeepsItsTime() {
        var timing = timed(at(18, 17), at(18, 18))
        timing.lastDay = at(21)
        XCTAssertEqual(timing.end, at(21, 18))
    }

    func testAnEndDayBeforeTheStartIsTheStartsDay() {
        var timing = timed(at(18, 17), at(20, 18))
        timing.lastDay = at(15)
        XCTAssertEqual(timing.end, at(18, 18))
        var overnight = timed(at(18, 23), at(19, 1))
        overnight.lastDay = at(18)
        XCTAssertEqual(overnight.end, at(19, 1), "01:00 on the start's day would be before the start")
    }

    func testAllDayShowsTheLastDayAndStoresTheNextMidnight() {
        let timing = EventTiming(start: at(18), end: at(21), isAllDay: true, calendar: calendar)
        XCTAssertEqual([timing.firstDay, timing.lastDay], [at(18), at(20)], "Starts 18 Oct, Ends 20 Oct")
        var moved = timing
        moved.firstDay = at(25)
        XCTAssertEqual([moved.start, moved.end], [at(25), at(28)], "the span of days goes along")
        moved.lastDay = at(20)
        XCTAssertEqual(moved.end, at(26), "never before the first day")
    }

    func testAllDayCoversTheDaysTheTimesTouched() {
        var timing = timed(at(18, 22), at(20, 6))
        timing.isAllDay = true
        XCTAssertEqual([timing.start, timing.end], [at(18), at(21)])
        var toMidnight = timed(at(18, 17), at(19, 0))
        toMidnight.isAllDay = true
        XCTAssertEqual(toMidnight.end, at(19), "an end at midnight does not touch the next day")
    }

    func testBackToTimedIsNineToTenOverTheSameDays() {
        var timing = EventTiming(start: at(18), end: at(21), isAllDay: true, calendar: calendar)
        timing.isAllDay = false
        XCTAssertEqual([timing.start, timing.end], [at(18, 9), at(20, 10)])
    }
}
