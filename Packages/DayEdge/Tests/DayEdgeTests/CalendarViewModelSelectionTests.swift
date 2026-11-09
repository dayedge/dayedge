import XCTest
@testable import Domain
@testable import Agenda

@MainActor
final class CalendarViewModelSelectionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    func testSelectingTheSelectedDayBringsItsMonthBackAfterAJump() {
        let viewModel = CalendarViewModel(calendar: calendar, visibleMonth: day(10, 1), selectedDate: day(10, 26))
        viewModel.jumpToMonth(day(12, 1))
        viewModel.select(date: day(10, 26))
        XCTAssertTrue(calendar.isDate(viewModel.visibleMonth, equalTo: day(10, 1), toGranularity: .month))
    }

    func testSelectingAnotherDayInTheShownMonthKeepsTheMonth() {
        let viewModel = CalendarViewModel(calendar: calendar, visibleMonth: day(10, 1), selectedDate: day(10, 26))
        viewModel.select(date: day(10, 3))
        XCTAssertTrue(calendar.isDate(viewModel.visibleMonth, equalTo: day(10, 1), toGranularity: .month))
        XCTAssertEqual(viewModel.selectedDate, day(10, 3))
    }
}
