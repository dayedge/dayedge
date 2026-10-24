import XCTest
@testable import Shell
@testable import Intelligence
@testable import Domain

final class SearchSuggestionTests: XCTestCase {
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

    func testJumpToDateToday() {
        let reference = date(2026, 9, 22)
        let title = SearchSuggestion.title(for: .jumpToDate(reference), referenceDate: reference, calendar: calendar, dates: dates)
        XCTAssertEqual(title, "Go to Today")
    }

    func testJumpToDateTomorrow() {
        let reference = date(2026, 9, 22)
        let title = SearchSuggestion.title(for: .jumpToDate(date(2026, 9, 23)), referenceDate: reference, calendar: calendar, dates: dates)
        XCTAssertEqual(title, "Go to Tomorrow")
    }

    func testJumpToDateYesterday() {
        let reference = date(2026, 9, 22)
        let title = SearchSuggestion.title(for: .jumpToDate(date(2026, 9, 21)), referenceDate: reference, calendar: calendar, dates: dates)
        XCTAssertEqual(title, "Go to Yesterday")
    }

    func testJumpToDateArbitraryWeekdaySameYear() {
        let reference = date(2026, 9, 22)
        let title = SearchSuggestion.title(for: .jumpToDate(date(2026, 9, 25)), referenceDate: reference, calendar: calendar, dates: dates)
        XCTAssertEqual(title, "Go to Friday 25 Sep")
    }

    func testJumpToDateDifferentYearIncludesYear() {
        let reference = date(2026, 9, 22)
        let title = SearchSuggestion.title(for: .jumpToDate(date(2027, 1, 2)), referenceDate: reference, calendar: calendar, dates: dates)
        XCTAssertEqual(title, "Go to Saturday 2 Jan 2027")
    }

    func testJumpToMonth() {
        let reference = date(2026, 9, 22)
        let title = SearchSuggestion.title(for: .jumpToMonth(date(2024, 9, 1)), referenceDate: reference, calendar: calendar, dates: dates)
        XCTAssertEqual(title, "Go to September 2024")
    }
}
