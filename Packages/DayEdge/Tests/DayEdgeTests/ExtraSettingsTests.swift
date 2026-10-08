import EventKit
import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

final class ExtraSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ExtraSettingsTests-\(UUID().uuidString)")!
    }

    // MARK: Badge

    func testBadgeStrategyDefaultAndPersistence() {
        let d = defaults()
        XCTAssertEqual(MenuBarBadgeSettings.strategy(defaults: d), .remainingEvents)
        for strategy in MenuBarBadgeStrategy.allCases {
            d.set(strategy.rawValue, forKey: MenuBarBadgeSettings.strategyKey)
            XCTAssertEqual(MenuBarBadgeSettings.strategy(defaults: d), strategy)
        }
        d.set("bogus", forKey: MenuBarBadgeSettings.strategyKey)
        XCTAssertEqual(MenuBarBadgeSettings.strategy(defaults: d), .remainingEvents)
    }

    // MARK: Call readiness

    func testCallLeadDefaultsAndClamps() {
        let d = defaults()
        XCTAssertEqual(CallReadinessSettings.leadMinutes(defaults: d), 15)
        d.set(10, forKey: CallReadinessSettings.leadMinutesKey)
        XCTAssertEqual(CallReadinessSettings.leadMinutes(defaults: d), 10)
        d.set(-3, forKey: CallReadinessSettings.leadMinutesKey)
        XCTAssertEqual(CallReadinessSettings.leadMinutes(defaults: d), 15)
        d.set(7, forKey: CallReadinessSettings.leadMinutesKey)
        XCTAssertEqual(CallReadinessSettings.leadMinutes(defaults: d), 15)
    }

    // MARK: Declined

    func testDeclinedPredicate() {
        XCTAssertTrue(DeclinedEventFilter.isDeclinedByUser(declinedByMe: true, isCanceledByOrganizer: false))
        XCTAssertFalse(DeclinedEventFilter.isDeclinedByUser(declinedByMe: true, isCanceledByOrganizer: true))
        XCTAssertFalse(DeclinedEventFilter.isDeclinedByUser(declinedByMe: false, isCanceledByOrganizer: false))
    }

    func testDeclinedSettingDefaultsOff() {
        let d = defaults()
        XCTAssertFalse(GeneralSettings.showsDeclined(defaults: d))
        d.set(true, forKey: GeneralSettings.showsDeclinedKey)
        XCTAssertTrue(GeneralSettings.showsDeclined(defaults: d))
    }

    // MARK: Day start

    func testDayStartHourDefaultsAndValidates() {
        let d = defaults()
        XCTAssertEqual(GeneralSettings.dayStartHour(defaults: d), 8)
        d.set(6, forKey: GeneralSettings.dayStartHourKey)
        XCTAssertEqual(GeneralSettings.dayStartHour(defaults: d), 6)
        d.set(3, forKey: GeneralSettings.dayStartHourKey)
        XCTAssertEqual(GeneralSettings.dayStartHour(defaults: d), 8)
    }

    func testDayScrollAnchor() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 14, minute: 30))!
        XCTAssertEqual(DayScrollAnchor.minutes(isToday: true, now: now, startHour: 8, calendar: calendar), 14 * 60 + 30)
        XCTAssertEqual(DayScrollAnchor.minutes(isToday: false, now: now, startHour: 9, calendar: calendar), 9 * 60)
    }

    // MARK: Week numbers

    private func gridDates(from start: DateComponents, calendar: Calendar) -> [Date] {
        let first = calendar.date(from: start)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    }

    func testMondayFirstMatchesISO() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        // Grid for September 2026 starts Monday 2026-08-31 (ISO week 36).
        let labels = WeekNumbers.labels(forGridStarting: gridDates(from: DateComponents(year: 2026, month: 8, day: 31), calendar: calendar), calendar: calendar)
        XCTAssertEqual(labels, [36, 37, 38, 39, 40, 41])
    }

    func testYearBoundaryMondayFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        // Row Mon 2026-12-28 … Sun 2027-01-03 is ISO week 53 of 2026.
        let labels = WeekNumbers.labels(forGridStarting: gridDates(from: DateComponents(year: 2026, month: 12, day: 28), calendar: calendar), calendar: calendar)
        XCTAssertEqual(labels.first, 53)
        XCTAssertEqual(labels[1], 1)
    }

    func testSundayFirstProducesOneLabelPerRow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1
        let labels = WeekNumbers.labels(forGridStarting: gridDates(from: DateComponents(year: 2026, month: 8, day: 30), calendar: calendar), calendar: calendar)
        XCTAssertEqual(labels.count, 6)
        XCTAssertEqual(labels, labels.sorted())
    }
}
