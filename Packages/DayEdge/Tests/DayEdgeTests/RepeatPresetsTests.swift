import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class RepeatPresetsTests: XCTestCase {
    private var dates: DatePresentationFormatter { DatePresentationFormatter(regionalLocale: Locale(identifier: "en_GB"), displayLocale: Locale(identifier: "en"), calendar: calendar) }
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()
    private var friday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 11))! }

    func testPresetsReadFromTheItemsDate() {
        let titles = RepeatPresets.options(anchor: friday, calendar: calendar, dates: dates).map(\.title)
        XCTAssertEqual(titles, ["Never", "Every Day", "Every Weekday", "Every Friday", "Every 2 Weeks",
                                "Every month on the 2nd", "Every year on 2 Oct"])
    }

    func testCurrentRulesFindTheirPreset() {
        let options = RepeatPresets.options(anchor: friday, calendar: calendar, dates: dates)
        func match(_ rule: TaskRecurrenceRule?) -> String? {
            RepeatPresets.option(matching: rule, in: options, anchor: friday, calendar: calendar)?.id
        }
        XCTAssertEqual(match(nil), "never")
        XCTAssertEqual(match(TaskRecurrenceRule(frequency: .weekly, weekdays: [.init(weekday: 6)])), "weekly",
                       "Friday named explicitly is still Every Friday")
        XCTAssertEqual(match(TaskRecurrenceRule(frequency: .monthly, daysOfMonth: [2])), "monthly")
        XCTAssertNil(match(TaskRecurrenceRule(frequency: .weekly, interval: 3)), "no preset: shown as its summary")
    }

    func testCustomDraftRoundTrips() {
        var draft = CustomRepeatDraft(rule: nil, anchor: friday, calendar: calendar)
        XCTAssertEqual(draft.weekdays, [6], "starts on the item's weekday")
        draft.interval = 2
        draft.weekdays = [2, 4]
        draft.ending = .afterCount(5)
        let rule = draft.rule
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.weekdays.map(\.weekday), [2, 4])
        XCTAssertEqual(rule.occurrenceCount, 5)
        XCTAssertEqual(CustomRepeatDraft(rule: rule, anchor: friday, calendar: calendar), draft)
    }

    func testDetailNavigationMovesWithoutWrapping() {
        let navigation = DetailNavigation(rows: ["title", "date", "time"])
        XCTAssertEqual(navigation.move(from: nil, by: 1), "title")
        XCTAssertEqual(navigation.move(from: nil, by: -1), "time")
        XCTAssertEqual(navigation.move(from: "date", by: 1), "time")
        XCTAssertEqual(navigation.move(from: "time", by: 1), "time")
        XCTAssertEqual(navigation.move(from: "title", by: -1), "title")
    }
}
