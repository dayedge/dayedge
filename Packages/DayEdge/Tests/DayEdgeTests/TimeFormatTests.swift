import XCTest
@testable import Shell
@testable import Domain

final class TimeFormatTests: XCTestCase {
    private let h24 = TimeFormat.twentyFourHour
    private let h12 = TimeFormat.twelveHour

    func testTwentyFourHourKeepsTheZeroPaddedClock() {
        XCTAssertEqual(h24.time(hour: 17, minute: 14), "17:14")
        XCTAssertEqual(h24.time(hour: 9, minute: 0), "09:00")
        XCTAssertEqual(h24.time(hour: 0, minute: 5), "00:05")
        XCTAssertEqual(h24.hour(9), "09:00")
    }

    func testTwelveHourIsCompactWithMinutesAlways() {
        XCTAssertEqual(h12.time(hour: 17, minute: 14), "5:14pm")
        XCTAssertEqual(h12.time(hour: 17, minute: 0), "5:00pm")
        XCTAssertEqual(h12.time(hour: 9, minute: 5), "9:05am")
        XCTAssertEqual(h12.time(hour: 0, minute: 0), "12:00am", "midnight")
        XCTAssertEqual(h12.time(hour: 12, minute: 0), "12:00pm", "noon")
        XCTAssertEqual(h12.time(hour: 12, minute: 30), "12:30pm")
        XCTAssertEqual(h12.hour(9), "9:00am")
        XCTAssertEqual(h12.hour(13), "1:00pm")
    }

    func testRangesNameTheHalfOfTheDayOnceWhenShared() {
        XCTAssertEqual(h12.range(fromHour: 10, fromMinute: 30, toHour: 10, toMinute: 55), "10:30–10:55am")
        XCTAssertEqual(h12.range(fromHour: 14, fromMinute: 0, toHour: 15, toMinute: 30), "2:00–3:30pm")
        XCTAssertEqual(h12.range(fromHour: 11, fromMinute: 30, toHour: 12, toMinute: 15), "11:30am–12:15pm")
        XCTAssertEqual(h24.range(fromHour: 10, fromMinute: 30, toHour: 10, toMinute: 55), "10:30 – 10:55")
    }

    func testMinutesSinceMidnight() {
        XCTAssertEqual(h12.time(minutesSinceMidnight: 17 * 60 + 14), "5:14pm")
        XCTAssertEqual(h24.time(minutesSinceMidnight: 17 * 60 + 14), "17:14")
    }

    func testDatesUseTheirCalendarsClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 17, minute: 14))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 18, minute: 0))!
        XCTAssertEqual(h12.time(date, calendar: calendar), "5:14pm")
        XCTAssertEqual(h24.time(date, calendar: calendar), "17:14")
        XCTAssertEqual(h12.range(date, end, calendar: calendar), "5:14–6:00pm")
    }

    func testSystemFollowsTheRegionsHourCycle() {
        func twelve(_ preference: TimeFormatPreference, _ id: String) -> Bool {
            TimeFormat.resolve(preference, locale: Locale(identifier: id)).uses12Hour
        }
        XCTAssertTrue(twelve(.system, "en_US"))
        XCTAssertFalse(twelve(.system, "en_GB"))
        XCTAssertFalse(twelve(.system, "pl_PL"))
        XCTAssertTrue(twelve(.twelveHour, "pl_PL"))
        XCTAssertFalse(twelve(.twentyFourHour, "en_US"))
    }

    func testThePreferenceDefaultsToSystem() {
        let defaults = UserDefaults(suiteName: "TimeFormatTests-\(UUID())")!
        XCTAssertEqual(GeneralSettings.timeFormat(defaults: defaults), .system)
        defaults.set(TimeFormatPreference.twelveHour.rawValue, forKey: GeneralSettings.timeFormatKey)
        XCTAssertEqual(GeneralSettings.timeFormat(defaults: defaults), .twelveHour)
    }

    // MARK: - Locales that write time their own way

    private func format(_ id: String, twelveHour: Bool) -> TimeFormat {
        TimeFormat.resolve(twelveHour ? .twelveHour : .twentyFourHour, locale: Locale(identifier: id))
    }

    func testTwentyFourHourUsesEachLocalesOwnClock() {
        XCTAssertEqual(format("pl_PL", twelveHour: false).time(hour: 17, minute: 14), "17:14")
        XCTAssertEqual(format("de_DE", twelveHour: false).time(hour: 9, minute: 5), "09:05")
        XCTAssertEqual(format("fi_FI", twelveHour: false).time(hour: 17, minute: 14), "17.14")
        // Arabic digits, as the locale writes them.
        XCTAssertTrue(format("ar_EG", twelveHour: false).time(hour: 17, minute: 14).contains("١٧"))
    }

    func testLatinTwelveHourLocalesGetTheCompactForm() {
        XCTAssertEqual(format("es_ES", twelveHour: true).time(hour: 17, minute: 14), "5:14pm", "\"p. m.\" → pm")
        XCTAssertEqual(format("en_GB", twelveHour: true).time(hour: 17, minute: 0), "5:00pm")
        XCTAssertEqual(format("pl_PL", twelveHour: true).time(hour: 9, minute: 30), "9:30am")
    }

    func testOtherTwelveHourLocalesKeepTheirMarkerWhereItBelongs() {
        let japanese = format("ja_JP", twelveHour: true)
        XCTAssertEqual(japanese.time(hour: 17, minute: 14), "午後5:14", "the marker leads in Japanese")
        XCTAssertTrue(japanese.range(fromHour: 15, fromMinute: 45, toHour: 16, toMinute: 45).contains("午後"))
        let korean = format("ko_KR", twelveHour: true).time(hour: 17, minute: 14)
        XCTAssertTrue(korean.hasPrefix("오후"), korean)
        let chinese = format("zh_CN", twelveHour: true).time(hour: 17, minute: 14)
        XCTAssertTrue(chinese.hasPrefix("下午"), chinese)
    }

    func testHourLabelsFollowTheLocaleToo() {
        XCTAssertEqual(format("fi_FI", twelveHour: false).hour(9), "9.00", "Finnish leaves the hour unpadded")
        XCTAssertTrue(format("ja_JP", twelveHour: true).hour(9).contains("午前"))
    }
}
