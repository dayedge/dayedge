import XCTest
@testable import Shell
@testable import Domain

final class WorkdayCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testSeptember2026HasTwentyTwoWeekdays() {
        let s = WorkdayCalculator.summary(forMonth: date(2026, 9, 10), weekendWeekdays: [1, 7], holidays: [], calendar: calendar)
        XCTAssertEqual(s.workingDays, 22)
        XCTAssertEqual(s.weekendDays, 8)
        XCTAssertEqual(s.publicHolidayCount, 0)
    }

    func testHolidayOnWorkdayIsSubtracted() {
        let h = [PublicHoliday(dateKey: "2026-09-16", name: "X")]
        let s = WorkdayCalculator.summary(forMonth: date(2026, 9, 1), weekendWeekdays: [1, 7], holidays: h, calendar: calendar)
        XCTAssertEqual(s.workingDays, 21)
        XCTAssertEqual(s.publicHolidayDates, [date(2026, 9, 16)])
        XCTAssertEqual(s.workdayLabel, "workdays")
        XCTAssertEqual(s.holidaySuffix, "1 holiday")
        XCTAssertEqual(s.breakdownLines, ["21 working days", "8 weekend days", "1 public holiday"])
    }

    func testHolidayOnWeekendIsNotDoubleCounted() {
        let h = [PublicHoliday(dateKey: "2026-09-19", name: "Sat")] // Saturday
        let s = WorkdayCalculator.summary(forMonth: date(2026, 9, 1), weekendWeekdays: [1, 7], holidays: h, calendar: calendar)
        XCTAssertEqual(s.workingDays, 22)
        XCTAssertEqual(s.weekendDays, 8)
        XCTAssertEqual(s.publicHolidayCount, 0)
        XCTAssertNil(s.holidaySuffix)
        XCTAssertEqual(s.holidayDetails.map(\.name), ["Sat"]) // still listed in details
    }

    func testSundayThursdayWorkWeek() {
        let s = WorkdayCalculator.summary(forMonth: date(2026, 9, 1), weekendWeekdays: [6, 7], holidays: [], calendar: calendar)
        XCTAssertEqual(s.weekendDays, 8) // Fridays + Saturdays in Sep 2026
        XCTAssertEqual(s.workingDays, 22)
    }

    func testDateKeyIsCivilDate() {
        XCTAssertEqual(WorkdayCalculator.dateKey(for: date(2026, 1, 5), calendar: calendar), "2026-01-05")
    }
}
