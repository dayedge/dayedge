import XCTest
@testable import Agenda

final class DayNumberRoleTests: XCTestCase {
    private func role(today: Bool = false, inMonth: Bool = true, weekend: Bool = false, holiday: Bool = false) -> DayNumberRole {
        DayNumberRole(isToday: today, isCurrentMonth: inMonth, isWeekend: weekend, isMarkedHoliday: holiday)
    }

    func testARegularWorkingDayIsRegular() {
        XCTAssertEqual(role(), .regular)
    }

    func testAWeekendIsAWeekend() {
        XCTAssertEqual(role(weekend: true), .weekend)
    }

    func testAHolidayOnAWorkingDayIsAHoliday() {
        XCTAssertEqual(role(holiday: true), .holiday)
    }

    func testTodayWinsOverAHoliday() {
        XCTAssertEqual(role(today: true, holiday: true), .today)
    }

    func testTodayWinsOverAWeekend() {
        XCTAssertEqual(role(today: true, weekend: true), .today)
    }

    func testADayOutsideTheMonthIsDimmedWhateverItIs() {
        XCTAssertEqual(role(inMonth: false, weekend: true, holiday: true), .outsideMonth)
    }
}
