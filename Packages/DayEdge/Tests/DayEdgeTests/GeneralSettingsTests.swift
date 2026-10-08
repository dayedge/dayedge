import EventKit
import XCTest
@testable import Shell
@testable import Domain
@testable import Platform

final class GeneralSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "GeneralSettingsTests-\(UUID().uuidString)")!
    }

    func testDefaults() {
        let d = defaults()
        XCTAssertEqual(GeneralSettings.defaultView(defaults: d), .month)
        XCTAssertEqual(GeneralSettings.weekStart(defaults: d), .system)
        XCTAssertTrue(GeneralSettings.showsWeather(defaults: d))
    }

    func testWeekStartMapping() {
        XCTAssertEqual(WeekStart.monday.firstWeekday(), 2)
        XCTAssertEqual(WeekStart.sunday.firstWeekday(), 1)
        XCTAssertEqual(WeekStart.system.firstWeekday(locale: Locale(identifier: "pl_PL")), 2)
        XCTAssertEqual(WeekStart.system.firstWeekday(locale: Locale(identifier: "en_US")), 1)
    }

    func testDefaultViewRoundTrip() {
        let d = defaults()
        d.set(ViewMode.day.settingsValue, forKey: GeneralSettings.defaultViewKey)
        XCTAssertEqual(GeneralSettings.defaultView(defaults: d), .day)
    }

    func testCalendarAccessMapping() {
        XCTAssertEqual(SourceAccessStatus.granted.title, "Full access")
        XCTAssertEqual(SourceAccessStatus.notDetermined.actionTitle, "Allow Access…")
        XCTAssertEqual(SourceAccessStatus.denied.actionTitle, "Open System Settings…")
        XCTAssertNil(SourceAccessStatus.granted.actionTitle)
        XCTAssertTrue(EventKitAccess.privacySettingsURL(for: .event).absoluteString.hasSuffix("Privacy_Calendars"))
        XCTAssertTrue(EventKitAccess.privacySettingsURL(for: .reminder).absoluteString.hasSuffix("Privacy_Reminders"))
    }
}
