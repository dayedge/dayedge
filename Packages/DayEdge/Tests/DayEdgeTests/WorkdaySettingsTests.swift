import XCTest
@testable import Shell
@testable import Domain

final class WorkdaySettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "WorkdaySettingsTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testDefaultsFollowLocaleRegion() {
        let c = WorkdaySettings.configuration(defaults: defaults(), locale: Locale(identifier: "pl_PL"))
        XCTAssertEqual(c.regionCode, "PL")
        XCTAssertEqual(c.weekendWeekdays, [1, 7])
        XCTAssertTrue(c.showCount)
        XCTAssertTrue(c.markHolidays)
    }

    func testExplicitOverridesWin() {
        let d = defaults()
        d.set("DE", forKey: WorkdaySettings.regionCodeKey)
        d.set(WorkWeek.sundayThursday.rawValue, forKey: WorkdaySettings.workWeekKey)
        d.set(false, forKey: WorkdaySettings.showCountKey)
        let c = WorkdaySettings.configuration(defaults: d, locale: Locale(identifier: "pl_PL"))
        XCTAssertEqual(c.regionCode, "DE")
        XCTAssertEqual(c.weekendWeekdays, [6, 7])
        XCTAssertFalse(c.showCount)
    }

    func testRegionOptionsFilterToSupported() {
        let options = HolidayRegionOption.options(supported: ["PL", "DE"], locale: Locale(identifier: "en_US"))
        XCTAssertEqual(Set(options.map(\.code)), ["PL", "DE"])
        XCTAssertEqual(options.first { $0.code == "PL" }?.flag, "🇵🇱")
    }
}
