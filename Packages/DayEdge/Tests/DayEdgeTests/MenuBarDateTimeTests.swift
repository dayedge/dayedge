import XCTest
@testable import Domain
@testable import Shell

final class MenuBarDateTimeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 6, minute: 7))!
    }

    private func formatter(region: String = "en_US", language: String = "en") -> DatePresentationFormatter {
        DatePresentationFormatter(regionalLocale: Locale(identifier: region), displayLocale: Locale(identifier: language), calendar: calendar)
    }

    private func text(_ format: MenuBarDateTimeFormat, formatter: DatePresentationFormatter? = nil,
                      time: TimeFormat = .twentyFourHour, pattern: String = "") -> String {
        format.text(at: now, pattern: pattern, formatter: formatter ?? self.formatter(), timeFormat: time)
    }

    func testCompactContainsDateAndTime() {
        XCTAssertEqual(text(.compact), "Oct 11  06:07")
    }

    func testDateContainsNoClock() {
        XCTAssertEqual(text(.date), "Oct 11")
    }

    func testTimeContainsNoDate() {
        XCTAssertEqual(text(.time), "06:07")
    }

    func testLongIncludesActualWeekday() {
        XCTAssertEqual(text(.long), "Sun, Oct 11  06:07")
    }

    func testDateUsesRegionalOrderWithEnglishNames() {
        XCTAssertEqual(text(.date, formatter: formatter(region: "pl_PL")), "11 Oct")
    }

    func testPolishDateUsesPolishMonth() {
        XCTAssertEqual(text(.date, formatter: formatter(region: "pl_PL", language: "pl")), "11 paź")
    }

    func testClockRespectsTwelveHourPreference() {
        XCTAssertEqual(text(.time, time: .twelveHour), "6:07am")
    }

    func testCustomCanContainOnlyTime() {
        XCTAssertEqual(text(.custom, pattern: "HH:mm"), "06:07")
    }

    func testInvalidStoredCustomUsesCompact() {
        XCTAssertEqual(text(.custom, pattern: "HH:mm:ss"), "Oct 11  06:07")
    }

    func testIconConfigurationProducesNoText() {
        XCTAssertEqual(MenuBarDateTimeConfiguration().text(at: now, formatter: formatter(), timeFormat: .twentyFourHour), "")
    }

    func testDateChangesAtMidnight() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(MenuBarDateTimeFormat.date.text(at: tomorrow, pattern: "", formatter: formatter(), timeFormat: .twentyFourHour), "Oct 12")
    }

    func testClockUsesInjectedTimeZone() {
        var local = formatter()
        local.calendar.timeZone = TimeZone(secondsFromGMT: 7200)!
        XCTAssertEqual(text(.time, formatter: local), "08:07")
    }

    func testSettingsDefaultToIconCompact() {
        let suite = "MenuBarDateTimeTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(MenuBarDateTimeSettings.configuration(defaults: defaults), MenuBarDateTimeConfiguration())
    }

    func testTimeOnlyPatternAcceptedForMenuBar() {
        XCTAssertTrue(DatePresentationFormatter.validate("HH:mm", sample: now, using: formatter(), purpose: .menuBar).isValid)
    }

    func testSecondsRejectedForMenuBar() {
        XCTAssertFalse(DatePresentationFormatter.validate("HH:mm:ss", sample: now, using: formatter(), purpose: .menuBar).isValid)
    }

    func testFractionalSecondsRejectedForMenuBar() {
        XCTAssertFalse(DatePresentationFormatter.validate("HH:mm SSS", sample: now, using: formatter(), purpose: .menuBar).isValid)
    }

    func testQuotedSecondsRemainLiteral() {
        XCTAssertTrue(DatePresentationFormatter.validate("HH:mm 'ss'", sample: now, using: formatter(), purpose: .menuBar).isValid)
    }

    func testUnclosedQuoteRejectedForMenuBar() {
        XCTAssertFalse(DatePresentationFormatter.validate("HH:mm 'oops", sample: now, using: formatter(), purpose: .menuBar).isValid)
    }
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "MenuBarPresentationTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testLegacyFalseMigratesToIcon() {
        withDefaults { defaults in
            defaults.set(false, forKey: MenuBarDateTimeSettings.legacyEnabledKey)
            XCTAssertEqual(MenuBarDateTimeSettings.presentation(defaults: defaults), .icon)
            XCTAssertEqual(defaults.string(forKey: MenuBarDateTimeSettings.presentationKey), "icon")
            XCTAssertNil(defaults.object(forKey: MenuBarDateTimeSettings.legacyEnabledKey))
        }
    }

    func testLegacyTrueMigratesToIconAndDateTime() {
        withDefaults { defaults in
            defaults.set(true, forKey: MenuBarDateTimeSettings.legacyEnabledKey)
            XCTAssertEqual(MenuBarDateTimeSettings.presentation(defaults: defaults), .iconAndDateTime)
        }
    }

    func testStoredModeWinsOverLegacyPreference() {
        withDefaults { defaults in
            defaults.set(MenuBarItemPresentation.dateTime.rawValue, forKey: MenuBarDateTimeSettings.presentationKey)
            defaults.set(false, forKey: MenuBarDateTimeSettings.legacyEnabledKey)
            XCTAssertEqual(MenuBarDateTimeSettings.presentation(defaults: defaults), .dateTime)
        }
    }

    func testMigrationPreservesFormatAndBadgePreferences() {
        withDefaults { defaults in
            defaults.set(true, forKey: MenuBarDateTimeSettings.legacyEnabledKey)
            defaults.set(MenuBarDateTimeFormat.custom.rawValue, forKey: MenuBarDateTimeSettings.formatKey)
            defaults.set("HH:mm", forKey: MenuBarDateTimeSettings.customPatternKey)
            defaults.set(MenuBarBadgeStrategy.dayOfMonth.rawValue, forKey: MenuBarBadgeSettings.strategyKey)
            let configuration = MenuBarDateTimeSettings.configuration(defaults: defaults)
            XCTAssertEqual(configuration.format, .custom)
            XCTAssertEqual(configuration.customPattern, "HH:mm")
            XCTAssertEqual(MenuBarBadgeSettings.strategy(defaults: defaults), .dayOfMonth)
        }
    }

    func testModeChangesPreserveHiddenPreferences() {
        withDefaults { defaults in
            defaults.set(MenuBarDateTimeFormat.long.rawValue, forKey: MenuBarDateTimeSettings.formatKey)
            defaults.set("d MMM HH:mm", forKey: MenuBarDateTimeSettings.customPatternKey)
            defaults.set(MenuBarBadgeStrategy.totalEvents.rawValue, forKey: MenuBarBadgeSettings.strategyKey)
            for mode in [MenuBarItemPresentation.dateTime, .icon, .iconAndDateTime] {
                defaults.set(mode.rawValue, forKey: MenuBarDateTimeSettings.presentationKey)
                _ = MenuBarDateTimeSettings.configuration(defaults: defaults)
            }
            XCTAssertEqual(MenuBarDateTimeSettings.configuration(defaults: defaults).format, .long)
            XCTAssertEqual(defaults.string(forKey: MenuBarDateTimeSettings.customPatternKey), "d MMM HH:mm")
            XCTAssertEqual(MenuBarBadgeSettings.strategy(defaults: defaults), .totalEvents)
        }
    }

    func testDateTimeModeHasTextWithoutIcon() {
        let configuration = MenuBarDateTimeConfiguration(presentation: .dateTime)
        XCTAssertFalse(configuration.presentation.showsIcon)
        XCTAssertEqual(configuration.text(at: now, formatter: formatter(), timeFormat: .twentyFourHour), "Oct 11  06:07")
    }

    func testCombinedModeHasIconAndText() {
        let configuration = MenuBarDateTimeConfiguration(presentation: .iconAndDateTime)
        XCTAssertTrue(configuration.presentation.showsIcon)
        XCTAssertEqual(configuration.text(at: now, formatter: formatter(), timeFormat: .twentyFourHour), "Oct 11  06:07")
    }

    func testIconModeKeepsBadgeVisible() {
        XCTAssertTrue(MenuBarItemPresentation.icon.showsIcon)
    }

}
