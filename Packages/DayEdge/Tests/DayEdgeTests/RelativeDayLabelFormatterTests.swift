import XCTest
@testable import Shell
@testable import Domain

final class RelativeDayLabelFormatterTests: XCTestCase {
    private var dates: DatePresentationFormatter { DatePresentationFormatter(regionalLocale: Locale(identifier: "en_GB"), displayLocale: Locale(identifier: "en"), calendar: calendar) }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testTomorrow() {
        XCTAssertEqual(
            RelativeDayLabelFormatter.dayReference(for: date(2026, 9, 23), relativeTo: date(2026, 9, 22), calendar: calendar, dates: dates),
            "Tomorrow"
        )
    }

    func testYesterday() {
        XCTAssertEqual(
            RelativeDayLabelFormatter.dayReference(for: date(2026, 9, 21), relativeTo: date(2026, 9, 22), calendar: calendar, dates: dates),
            "Yesterday"
        )
    }

    func testWithinSixDaysSameMonthUsesShortWeekday() {
        // 22 Sep 2026 is a Tuesday; +3 days lands on Friday.
        XCTAssertEqual(
            RelativeDayLabelFormatter.dayReference(for: date(2026, 9, 25), relativeTo: date(2026, 9, 22), calendar: calendar, dates: dates),
            "Fri"
        )
    }

    func testCrossingMonthUsesCompactDateEvenWithinSixDays() {
        // 29 Sep -> 3 Oct is only 4 days but crosses the month boundary.
        XCTAssertEqual(
            RelativeDayLabelFormatter.dayReference(for: date(2026, 10, 3), relativeTo: date(2026, 9, 29), calendar: calendar, dates: dates),
            "3 Oct"
        )
    }

    func testSameMonthBeyondSixDaysUsesCompactDate() {
        XCTAssertEqual(
            RelativeDayLabelFormatter.dayReference(for: date(2026, 9, 30), relativeTo: date(2026, 9, 22), calendar: calendar, dates: dates),
            "30 Sep"
        )
    }

    func testCrossingYearIncludesTheYear() {
        XCTAssertEqual(
            RelativeDayLabelFormatter.dayReference(for: date(2027, 1, 2), relativeTo: date(2026, 12, 31), calendar: calendar, dates: dates),
            "2 Jan 2027"
        )
    }

    func testFarFutureDifferentYearIncludesTheYear() {
        XCTAssertEqual(
            RelativeDayLabelFormatter.dayReference(for: date(2027, 2, 18), relativeTo: date(2026, 9, 22), calendar: calendar, dates: dates),
            "18 Feb 2027"
        )
    }

    func testSameDayIsNotTomorrow() {
        XCTAssertNotEqual(
            RelativeDayLabelFormatter.dayReference(for: date(2026, 9, 22), relativeTo: date(2026, 9, 22), calendar: calendar, dates: dates),
            "Tomorrow"
        )
    }
}
