import XCTest
@testable import Shell
@testable import Domain
@testable import UI
@testable import Intelligence

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
        let rule = draft.rule(calendar: calendar)
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.weekdays.map(\.weekday), [2, 4])
        XCTAssertEqual(rule.occurrenceCount, 5)
        XCTAssertEqual(CustomRepeatDraft(rule: rule, anchor: friday, calendar: calendar), draft)
    }

    /// The Custom… page and Quick Add's End Repeat store the same end for the same last day: all of it, so an
    /// occurrence late that day still counts, whatever time the date picker carried.
    func testACustomEndDateIsTheWholeLastDayAsQuickAddStoresIt() throws {
        var draft = CustomRepeatDraft(rule: nil, anchor: friday, calendar: calendar)
        var endRepeat = RepeatEdit(rule: nil, calendar: calendar)
        endRepeat.startEnd(firstDay: friday, calendar: calendar)
        XCTAssertEqual(draft.suggestedEnd, endRepeat.lastDay, "On Date starts where End Repeat does")
        XCTAssertEqual(draft.suggestedEnd, calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        let lastDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: friday))
        draft.ending = .onDate(try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: lastDay)))
        var quickAdd = RepeatEdit(rule: nil, calendar: calendar)
        quickAdd.recurrence = .weekly
        quickAdd.lastDay = calendar.startOfDay(for: lastDay)
        let custom = try XCTUnwrap(draft.rule(calendar: calendar).endDate)
        XCTAssertEqual(custom, quickAdd.rule(firstDay: friday, calendar: calendar)?.endDate)
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: custom), DateComponents(hour: 23, minute: 59))
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
