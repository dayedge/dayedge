import XCTest
@testable import Shell
@testable import Domain

final class DatePresentationFormatterTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private var wednesday: Date { date(2026, 10, 7) }
    private var now: Date { date(2026, 10, 6) }

    private func formatter(_ region: String) -> DatePresentationFormatter {
        DatePresentationFormatter(regionalLocale: Locale(identifier: region), calendar: calendar)
    }

    func testStandardFollowsTheRegionsOrderInEnglish() {
        XCTAssertEqual(formatter("en_GB").format(wednesday, .standard), "Wednesday 7 October 2026")
        XCTAssertEqual(formatter("pl_PL").format(wednesday, .standard), "Wednesday 7 October 2026")
        XCTAssertEqual(formatter("en_US").format(wednesday, .standard), "Wednesday October 7 2026")
        XCTAssertEqual(formatter("de_DE").format(wednesday, .standard), "Wednesday 7 October 2026")
        XCTAssertEqual(formatter("hu_HU").format(wednesday, .standard), "Wednesday 2026 October 7")
        XCTAssertEqual(formatter("ja_JP").format(wednesday, .standard), "Wednesday 2026 October 7")
    }

    func testRegionalWordsAndPunctuationNeverLeakIn() {
        for region in ["es_ES", "ja_JP", "zh_CN", "ko_KR", "lt_LT", "fi_FI", "hu_HU", "de_DE", "en_US", "pl_PL"] {
            for style in [DateStyle.standard, .compact, .short] {
                let text = formatter(region).format(wednesday, style, relativeTo: now)
                XCTAssertFalse(text.contains(","), "\(region) \(style): \(text)")
                XCTAssertFalse(text.contains("."), "\(region) \(style): \(text)")
                XCTAssertFalse(text.contains("  "), "\(region) \(style): \(text)")
                XCTAssertTrue(text.unicodeScalars.allSatisfy(\.isASCII), "\(region) \(style): \(text)")
                XCTAssertFalse(text.contains(" de "), "\(region) \(style): \(text)")
            }
        }
    }

    func testCompactNamesTheYearOnlyOutsideTheCurrentOne() {
        let gb = formatter("en_GB"), us = formatter("en_US")
        XCTAssertEqual(gb.format(wednesday, .compact, relativeTo: now), "Wednesday 7 Oct")
        XCTAssertEqual(us.format(wednesday, .compact, relativeTo: now), "Wednesday Oct 7")
        XCTAssertEqual(gb.format(date(2027, 10, 7), .compact, relativeTo: now), "Thursday 7 Oct 2027")
        XCTAssertEqual(gb.format(wednesday, .compact, weekday: .abbreviated, relativeTo: now), "Wed 7 Oct")
        XCTAssertEqual(us.format(wednesday, .compact, weekday: .abbreviated, relativeTo: now), "Wed Oct 7")
        XCTAssertEqual(gb.format(wednesday, .compact, relativeTo: now).uppercased(), "WEDNESDAY 7 OCT")
    }

    func testShortHasNoWeekday() {
        XCTAssertEqual(formatter("en_GB").format(wednesday, .short, relativeTo: now), "7 Oct")
        XCTAssertEqual(formatter("en_US").format(wednesday, .short, relativeTo: now), "Oct 7")
        XCTAssertEqual(formatter("en_GB").format(wednesday, .short, year: .always, relativeTo: now), "7 Oct 2026")
        XCTAssertEqual(formatter("en_GB").format(date(2025, 1, 2), .short, relativeTo: now), "2 Jan 2025")
    }

    func testParts() {
        let gb = formatter("en_GB")
        XCTAssertEqual(gb.weekday(wednesday, .full), "Wednesday")
        XCTAssertEqual(gb.weekday(wednesday, .abbreviated), "Wed")
        XCTAssertEqual(gb.month(wednesday, abbreviated: false), "October")
        XCTAssertEqual(gb.month(wednesday, abbreviated: true), "Oct")
        XCTAssertEqual(gb.day(wednesday), "7")
        XCTAssertEqual(gb.monthYear(wednesday), "October 2026")
        XCTAssertEqual(formatter("ja_JP").monthYear(wednesday), "2026 October")
    }

    func testWeekdaySymbolsStartOnTheCalendarsFirstDay() {
        XCTAssertEqual(formatter("pl_PL").weekdaySymbols(.abbreviated).first, "Mon")
        var sunday = calendar
        sunday.firstWeekday = 1
        let us = DatePresentationFormatter(regionalLocale: Locale(identifier: "en_US"), calendar: sunday)
        XCTAssertEqual(us.weekdaySymbols(.full), ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"])
    }

    func testRelativeDaysAreEnglish() {
        let gb = formatter("pl_PL")
        XCTAssertEqual(gb.relativeDay(now, relativeTo: now), "Today")
        XCTAssertEqual(gb.relativeDay(wednesday, relativeTo: now), "Tomorrow")
        XCTAssertEqual(gb.relativeDay(date(2026, 10, 5), relativeTo: now), "Yesterday")
        XCTAssertNil(gb.relativeDay(date(2026, 10, 9), relativeTo: now))
    }

    func testCustomPatterns() {
        let gb = formatter("en_GB")
        XCTAssertEqual(gb.format(wednesday, .custom("yyyy-MM-dd")), "2026-10-07")
        XCTAssertEqual(gb.format(wednesday, .custom("EEE d MMM")), "Wed 7 Oct")
        var custom = gb
        custom.customStandard = "EEEE d MMMM"
        custom.customCompact = "d/M"
        XCTAssertEqual(custom.format(wednesday, .standard), "Wednesday 7 October")
        XCTAssertEqual(custom.format(wednesday, .compact), "7/10")
        XCTAssertEqual(custom.format(wednesday, .short, relativeTo: now), "7 Oct", "short isn't customizable")
    }

    func testValidation() {
        func valid(_ pattern: String) -> Bool { DatePresentationFormatter.validate(pattern, sample: wednesday).isValid }
        XCTAssertEqual(DatePresentationFormatter.validate("EEEE d MMMM yyyy", sample: wednesday,
                                                          using: formatter("en_GB")), .valid(preview: "Wednesday 7 October 2026"))
        XCTAssertTrue(valid("EEE d MMM"))
        XCTAssertTrue(valid("yyyy-MM-dd"))
        XCTAssertTrue(valid("d 'of' MMMM"), "quoted literals")
        XCTAssertTrue(valid("d MMM ''yy"), "an escaped quote")
        XCTAssertTrue(valid("MMMM"), "a display pattern may leave out the day and year")
        XCTAssertFalse(valid(""))
        XCTAssertFalse(valid("d 'of MMMM"), "an open quote")
        XCTAssertFalse(valid("d MMM T"), "not a field")
        XCTAssertFalse(valid("HH:mm"), "time only")
        XCTAssertFalse(valid("'today'"), "no field at all")
    }

    func testStoredPatternsAreUsedOnlyWhenValid() {
        let defaults = UserDefaults(suiteName: "DatePresentationFormatterTests-\(UUID())")!
        XCTAssertNil(DatePresentationFormatter.stored(defaults: defaults).customStandard)
        defaults.set("EEE d MMM", forKey: GeneralSettings.dateFormatStandardKey)
        defaults.set("d 'oops", forKey: GeneralSettings.dateFormatCompactKey)
        let stored = DatePresentationFormatter.stored(defaults: defaults)
        XCTAssertEqual(stored.customStandard, "EEE d MMM")
        XCTAssertNil(stored.customCompact)
    }
}
