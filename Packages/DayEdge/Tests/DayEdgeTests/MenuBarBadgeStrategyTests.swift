import XCTest
@testable import Shell
@testable import Domain

final class MenuBarBadgeStrategyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(day: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private func events(_ count: Int) -> [AgendaEventModel] {
        (0..<count).map {
            AgendaEventModel(id: "event-\($0)", startTime: "13:00", endTime: "14:00", title: "Event", myResponseStatus: .accepted)
        }
    }

    private func content(_ strategy: MenuBarBadgeStrategy, count: Int = 0, day: Int = 11) -> MenuBarBadgeContent {
        strategy.badgeContent(events: events(count), now: date(day: day), calendar: calendar)
    }

    func testRemainingEventCountCapsAtNineWithOverflow() {
        XCTAssertEqual(content(.remainingEvents, count: 12), MenuBarBadgeContent(number: 9, isOverflow: true))
    }

    func testAcceptedEventCountCapsAtNineWithOverflow() {
        XCTAssertEqual(content(.acceptedEvents, count: 12), MenuBarBadgeContent(number: 9, isOverflow: true))
    }

    func testAcceptedRemainingEventCountCapsAtNineWithOverflow() {
        XCTAssertEqual(content(.acceptedRemainingEvents, count: 12), MenuBarBadgeContent(number: 9, isOverflow: true))
    }

    func testTotalEventCountCapsAtNineWithOverflow() {
        XCTAssertEqual(content(.totalEvents, count: 12), MenuBarBadgeContent(number: 9, isOverflow: true))
    }

    func testExactlyNineEventsHaveNoOverflow() {
        XCTAssertEqual(content(.totalEvents, count: 9), MenuBarBadgeContent(number: 9, isOverflow: false))
    }

    func testZeroEventsShowZeroWithoutOverflow() {
        XCTAssertEqual(content(.remainingEvents), MenuBarBadgeContent(number: 0, isOverflow: false))
    }

    func testSingleDigitDateHasNoOverflow() {
        XCTAssertEqual(content(.dayOfMonth, day: 1), MenuBarBadgeContent(number: 1, isOverflow: false))
    }

    func testDayTenIsNotCappedOrMarkedAsOverflow() {
        XCTAssertEqual(content(.dayOfMonth, day: 10), MenuBarBadgeContent(number: 10, isOverflow: false))
    }

    func testDayThirtyOneIsNotCappedOrMarkedAsOverflow() {
        XCTAssertEqual(content(.dayOfMonth, day: 31), MenuBarBadgeContent(number: 31, isOverflow: false))
    }

    func testDateIgnoresTheEventCount() {
        XCTAssertEqual(content(.dayOfMonth, count: 12), MenuBarBadgeContent(number: 11, isOverflow: false))
    }

    func testTwoDigitDateDoesNotResolveToAnOverflowGlyph() {
        let badge = content(.dayOfMonth, day: 31)
        XCTAssertNil(MenuBarCornerGlyph.resolve(MenuBarCornerGlyphInputs(isOverflow: badge.isOverflow)))
    }

    func testTwoDigitDateStillAllowsTheTaskGlyph() {
        let badge = content(.dayOfMonth, day: 31)
        XCTAssertEqual(MenuBarCornerGlyph.resolve(MenuBarCornerGlyphInputs(isOverflow: badge.isOverflow, hasTasksDueToday: true)), .tasksDue)
    }
}
