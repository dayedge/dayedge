import XCTest
@testable import Agenda

final class DayHeaderViewTests: XCTestCase {
    private let english = Locale(identifier: "en")
    private let polish = Locale(identifier: "pl")

    func testEmptyDaySaysNoEvents() {
        XCTAssertEqual(DayHeaderView.countText(events: 0, tasks: 0, locale: english), "No events")
    }

    func testEmptyDaySaysNoEventsInPolish() {
        XCTAssertEqual(DayHeaderView.countText(events: 0, tasks: 0, locale: polish), "Brak wydarzeń")
    }

    func testDayWithOnlyTasksShowsJustTheTaskCount() {
        XCTAssertEqual(DayHeaderView.countText(events: 0, tasks: 2, locale: english), "2 tasks")
    }
}
