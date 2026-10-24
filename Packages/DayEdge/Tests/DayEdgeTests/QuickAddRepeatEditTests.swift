import XCTest
import TimeWhisper
@testable import Domain
@testable import Intelligence

/// Quick Add's Repeat and End Repeat: a parsed end shows on its own row, survives another Repeat choice, and is
/// saved as the end of its last day.
final class QuickAddRepeatEditTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return value
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// "cycling club next week on monday 11-12, then every second week till end of the year", as the parser reads it.
    private func cyclingClub() throws -> EventQuickAddEdit {
        let everyOtherWeek = RecurrenceSpec(frequency: .weekly, interval: 2, until: CivilDate(year: 2026, month: 12, day: 31))
        let spec = EventSpec(title: "Cycling club", time: .timed(
            start: Moment(date: date(10, 19, 11), timeZoneID: "Europe/Warsaw", offsetSeconds: 7200),
            endExclusive: Moment(date: date(10, 19, 12), timeZoneID: "Europe/Warsaw", offsetSeconds: 7200)), recurrence: everyOtherWeek)
        guard case .event(let event) = try QuickAddCandidate(Candidate(content: .event(spec)), calendar: calendar) else {
            XCTFail("Expected an event")
            throw CancellationError()
        }
        return EventQuickAddEdit(draft: event, calendar: calendar)
    }

    func testAParsedEndShowsApartFromHowOften() throws {
        let edit = try cyclingClub()
        XCTAssertEqual(edit.repeating.recurrence, .biweekly, "a menu value, not a custom one carrying the end")
        XCTAssertEqual(edit.repeating.lastDay, date(12, 31))
        let rule = try XCTUnwrap(edit.eventDraft(calendar: calendar).recurrenceRule)
        XCTAssertEqual(rule.endDate, date(12, 31, 24).addingTimeInterval(-1), "the end of the last day")
    }

    func testAnotherRepeatKeepsTheEndAndNeverDropsIt() throws {
        var edit = try cyclingClub()
        edit.repeating.recurrence = .weekly
        XCTAssertEqual(edit.eventDraft(calendar: calendar).recurrenceRule?.endDate, date(12, 31, 24).addingTimeInterval(-1))
        edit.repeating.lastDay = nil
        XCTAssertNil(edit.eventDraft(calendar: calendar).recurrenceRule?.endDate)
        edit.repeating.recurrence = .never
        XCTAssertNil(edit.eventDraft(calendar: calendar).recurrenceRule, "no repeat, no rule")
    }

    func testAnEndBeforeTheFirstDayIsNoEnd() throws {
        var edit = try cyclingClub()
        edit.timing.firstDay = date(12, 31).addingTimeInterval(86_400 * 7)
        XCTAssertNil(edit.eventDraft(calendar: calendar).recurrenceRule?.endDate)
    }

    func testACustomRuleKeepsItsShapeAndItsEnd() {
        let parsed = TaskRecurrenceRule(frequency: .weekly, interval: 3, weekdays: [.init(weekday: 2)], endDate: date(11, 30, 12))
        let repeating = RepeatEdit(rule: parsed, calendar: calendar)
        XCTAssertTrue(repeating.recurrence.isCustom)
        XCTAssertEqual(repeating.options.last, repeating.recurrence, "offered while selected")
        XCTAssertEqual(repeating.rule(firstDay: date(10, 5), calendar: calendar),
                       parsed.ending(on: date(11, 30), calendar: calendar))
    }

    func testATaskRepeatsOnlyWithADueDate() {
        let rule = TaskRecurrenceRule(frequency: .daily, endDate: date(10, 10))
        var edit = QuickAddEdit(draft: TaskDraft(title: "Stretch", dueDate: date(10, 1), recurrenceRule: rule),
                                calendar: calendar, referenceDate: date(9, 23))
        XCTAssertEqual(edit.taskDraft(calendar: calendar).recurrenceRule?.endDate, date(10, 11).addingTimeInterval(-1))
        edit.day = nil
        XCTAssertNil(edit.taskDraft(calendar: calendar).recurrenceRule)
    }

    func testSteppingTheEnd() {
        var repeating = RepeatEdit(rule: TaskRecurrenceRule(frequency: .weekly), calendar: calendar)
        repeating.stepEnd(days: 1, firstDay: date(10, 19), calendar: calendar)
        XCTAssertNil(repeating.lastDay, "Never stays Never")
        repeating.startEnd(firstDay: date(10, 19), calendar: calendar)
        XCTAssertEqual(repeating.lastDay, date(11, 19), "from Never, a month after the first day")
        repeating.stepEnd(days: -7, firstDay: date(10, 19), calendar: calendar)
        XCTAssertEqual(repeating.lastDay, date(11, 12))
        repeating.stepEnd(days: -70, firstDay: date(10, 19), calendar: calendar)
        XCTAssertEqual(repeating.lastDay, date(10, 19), "never before the first day")
    }

    /// Alert changes the first alert the text named and keeps the others; None removes only it.
    func testAlertEditsTheFirstParsedAlert() {
        let start = date(10, 5, 9)
        let parsed = EventDraft(title: "Standup", start: start, end: start.addingTimeInterval(1800), isAllDay: false,
                                alerts: [.before(minutes: 15), .at(date(10, 5, 8))])
        var edit = EventQuickAddEdit(draft: parsed, calendar: calendar)
        XCTAssertEqual(edit.firstAlert, .before(minutes: 15))
        edit.firstAlert = .before(minutes: 5)
        XCTAssertEqual(edit.eventDraft(calendar: calendar).alerts, [.before(minutes: 5), .at(date(10, 5, 8))])
        edit.firstAlert = nil
        XCTAssertEqual(edit.alerts, [.at(date(10, 5, 8))])
        edit.alerts = []
        edit.firstAlert = .before(minutes: 0)
        XCTAssertEqual(edit.alerts, [.before(minutes: 0)])

        let line = PaletteActions.summary(of: parsed, recurrence: nil, calendars: [], referenceDate: date(10, 1), calendar: calendar)
        XCTAssertTrue(line.hasSuffix(" · Alert 15 minutes before"), line)
    }

    func testEndRepeatFollowsRepeatInTabOrder() {
        typealias Field = QuickAddField
        XCTAssertEqual(Field.next(after: .recurrence, in: Field.order(hasDate: true, repeats: true), backward: false), .repeatEnd)
        XCTAssertEqual(Field.next(after: .repeatEnd, in: Field.order(hasDate: true, repeats: true), backward: false), .title, "wraps")
        XCTAssertEqual(Field.eventOrder(isAllDay: false, repeats: true).suffix(3), [.recurrence, .repeatEnd, .alert])
        XCTAssertFalse(Field.eventOrder(isAllDay: true, repeats: false).contains(.repeatEnd), "only while it repeats")
    }
}
