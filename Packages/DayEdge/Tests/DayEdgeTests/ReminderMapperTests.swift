import EventKit
import XCTest
@testable import Shell
@testable import Domain
@testable import Platform

final class ReminderMapperTests: XCTestCase {
    private let store = EKEventStore()
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func reminder(_ title: String = "Task") -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        return reminder
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int? = nil, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: h == nil ? nil : min))!
    }

    private func write(_ change: TaskChange, to reminder: EKReminder) throws {
        try ReminderMapper.write(change, to: reminder, calendar: calendar, eventStore: store)
    }

    private func item(_ reminder: EKReminder) -> TaskItem {
        ReminderMapper.taskItem(from: reminder, calendar: calendar)
    }

    // MARK: Priority

    func testPriorityBucketsFollowReminders() {
        XCTAssertEqual(ReminderMapper.priority(fromEventKit: 0), .none)
        for value in 1...4 { XCTAssertEqual(ReminderMapper.priority(fromEventKit: value), .high) }
        XCTAssertEqual(ReminderMapper.priority(fromEventKit: 5), .medium)
        for value in 6...9 { XCTAssertEqual(ReminderMapper.priority(fromEventKit: value), .low) }
        XCTAssertEqual([TaskPriority.none, .low, .medium, .high].map(ReminderMapper.eventKitPriority), [0, 9, 5, 1])
    }

    // MARK: Due date

    func testDateOnlyDueIsFloatingAndHasNoTime() throws {
        let reminder = reminder()
        try write(.due(date(2026, 9, 28), hasTime: false), to: reminder)
        XCTAssertNil(reminder.dueDateComponents?.hour)
        XCTAssertNil(reminder.dueDateComponents?.timeZone)
        let result = item(reminder)
        XCTAssertEqual(result.dueDate, date(2026, 9, 28))
        XCTAssertFalse(result.hasDueTime)
    }

    func testFloatingDueUsesTheReadersZoneDespiteEventKitCalendarMetadata() {
        var metadataCalendar = Calendar(identifier: .gregorian)
        metadataCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(calendar: metadataCalendar, year: 2026, month: 9, day: 28)
        let result = ReminderMapper.dueDate(from: components, calendar: calendar)
        XCTAssertEqual(result.date, date(2026, 9, 28))
        XCTAssertFalse(result.hasTime)
    }

    func testTimedDueUsesItsExplicitZoneDespiteTheReadersZone() {
        let zone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(timeZone: zone, year: 2026, month: 9, day: 28, hour: 14, minute: 30)
        var utc = calendar
        utc.timeZone = zone
        let result = ReminderMapper.dueDate(from: components, calendar: calendar)
        XCTAssertEqual(result.date, utc.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 14, minute: 30)))
        XCTAssertTrue(result.hasTime)
    }

    func testTimedDueKeepsTimeAndZone() throws {
        let reminder = reminder()
        try write(.due(date(2026, 9, 28, 14, 30), hasTime: true), to: reminder)
        XCTAssertEqual(reminder.dueDateComponents?.hour, 14)
        XCTAssertEqual(reminder.dueDateComponents?.timeZone, calendar.timeZone)
        let result = item(reminder)
        XCTAssertEqual(result.dueDate, date(2026, 9, 28, 14, 30))
        XCTAssertTrue(result.hasDueTime)
    }

    func testClearingDueDropsRepeatAndPinsTheAlert() throws {
        let reminder = reminder()
        try write(.due(date(2026, 9, 28, 9), hasTime: true), to: reminder)
        try write(.recurrence(.weekly), to: reminder)
        try write(.alert(.relative(minutesBefore: 15)), to: reminder)
        XCTAssertEqual(item(reminder).recurrence, .weekly)
        XCTAssertEqual(item(reminder).alert, .relative(minutesBefore: 15))

        try write(.due(nil, hasTime: false), to: reminder)
        XCTAssertNil(reminder.dueDateComponents)
        XCTAssertEqual(item(reminder).recurrence, .never)
        XCTAssertTrue(reminder.recurrenceRules?.isEmpty ?? true)
        XCTAssertEqual(item(reminder).alert, .absolute(date(2026, 9, 28, 8, 45)), "kept as the same moment, like the model does")
    }

    func testRemovingTimeKeepsTheAlertAsTheSameMoment() throws {
        let reminder = reminder()
        try write(.due(date(2026, 9, 28, 9), hasTime: true), to: reminder)
        try write(.alert(.relative(minutesBefore: 60)), to: reminder)
        try write(.due(date(2026, 9, 28), hasTime: false), to: reminder)
        XCTAssertEqual(item(reminder).alert, .absolute(date(2026, 9, 28, 8)))
    }

    // MARK: Recurrence

    func testStandardRepeatsRoundTrip() throws {
        for recurrence in [TaskRecurrence.daily, .weekdays, .weekly, .biweekly, .monthly, .yearly] {
            let reminder = reminder()
            try write(.due(date(2026, 9, 28), hasTime: false), to: reminder) // a Monday
            try write(.recurrence(recurrence), to: reminder)
            XCTAssertEqual(item(reminder).recurrence, recurrence, "\(recurrence)")
        }
    }

    func testChoosingNeverRemovesTheRule() throws {
        let reminder = reminder()
        try write(.due(date(2026, 9, 28), hasTime: false), to: reminder)
        try write(.recurrence(.daily), to: reminder)
        try write(.recurrence(.never), to: reminder)
        XCTAssertTrue(reminder.recurrenceRules?.isEmpty ?? true)
    }

    func testRepeatWithoutADueDateIsRefused() throws {
        let reminder = reminder()
        try write(.recurrence(.daily), to: reminder)
        XCTAssertTrue(reminder.recurrenceRules?.isEmpty ?? true)
    }

    func testCustomRulesAreShownAndSurviveUnrelatedEdits() throws {
        let reminder = reminder()
        try write(.due(date(2026, 9, 28), hasTime: false), to: reminder)
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .monthly, interval: 3, end: nil))
        XCTAssertEqual(item(reminder).recurrence, .custom("Every 3 months"))

        try write(.priority(.high), to: reminder)
        try write(.title("Renamed"), to: reminder)
        try write(.recurrence(.custom("Every 3 months")), to: reminder) // "no choice made"
        XCTAssertEqual(reminder.recurrenceRules?.first?.interval, 3)

        try write(.recurrence(.weekly), to: reminder) // an explicit pick replaces it
        XCTAssertEqual(item(reminder).recurrence, .weekly)
    }

    func testRuleWithAnEndIsCustomNotFlattened() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 5))
        XCTAssertEqual(ReminderMapper.recurrence(from: [rule], due: nil, calendar: calendar), .custom("Every day, 5 times"))
    }

    func testWeeklyOnASpecificDayIsCustomUnlessItIsTheDueDay() {
        let tuesday = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday)], daysOfTheMonth: nil,
            monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil
        )
        XCTAssertEqual(ReminderMapper.recurrence(from: [tuesday], due: date(2026, 9, 29), calendar: calendar), .weekly)
        XCTAssertEqual(ReminderMapper.recurrence(from: [tuesday], due: date(2026, 9, 28), calendar: calendar), .custom("Every week on Tue"))
    }

    // MARK: Alerts

    func testAlertsMapBothWays() throws {
        let reminder = reminder()
        try write(.due(date(2026, 9, 28, 9), hasTime: true), to: reminder)
        try write(.alert(.relative(minutesBefore: 30)), to: reminder)
        XCTAssertEqual(reminder.alarms?.first?.relativeOffset, -1800)
        XCTAssertEqual(item(reminder).alert, .relative(minutesBefore: 30))

        let moment = date(2026, 9, 27, 18)
        try write(.alert(.absolute(moment)), to: reminder)
        XCTAssertEqual(reminder.alarms?.count, 1, "replaced, not stacked")
        XCTAssertEqual(item(reminder).alert, .absolute(moment))

        try write(.alert(nil), to: reminder)
        XCTAssertTrue(reminder.alarms?.isEmpty ?? true)
    }

    func testLocationAlarmsAreLeftAlone() throws {
        let reminder = reminder()
        let location = EKAlarm()
        location.structuredLocation = EKStructuredLocation(title: "Home")
        location.proximity = .enter
        reminder.addAlarm(location)
        XCTAssertNil(item(reminder).alert)

        try write(.due(date(2026, 9, 28, 9), hasTime: true), to: reminder)
        try write(.alert(.relative(minutesBefore: 5)), to: reminder)
        XCTAssertEqual(reminder.alarms?.count, 2)
        try write(.alert(nil), to: reminder)
        XCTAssertEqual(reminder.alarms?.count, 1)
        XCTAssertNotNil(reminder.alarms?.first?.structuredLocation)
    }

    // MARK: Other fields

    func testTitleNotesUrlAndCompletion() throws {
        let reminder = reminder("Old")
        try write(.title("  New  "), to: reminder)
        XCTAssertEqual(reminder.title, "New")
        try write(.title("   "), to: reminder)
        XCTAssertEqual(reminder.title, "New", "an empty title is refused, like in Reminders")

        try write(.notes("Hello"), to: reminder)
        XCTAssertEqual(item(reminder).notes, "Hello")
        try write(.notes("   "), to: reminder)
        XCTAssertNil(item(reminder).notes)

        let url = URL(string: "https://example.com")!
        try write(.url(url), to: reminder)
        XCTAssertEqual(item(reminder).url, url)

        try write(.completed(true), to: reminder)
        XCTAssertTrue(item(reminder).isCompleted)
        XCTAssertNotNil(item(reminder).completionDate)
        try write(.completed(false), to: reminder)
        XCTAssertFalse(item(reminder).isCompleted)
        XCTAssertNil(item(reminder).completionDate)
    }

    func testMovingToAnUnknownListIsNotFound() {
        let reminder = reminder()
        XCTAssertThrowsError(try write(.list("nope"), to: reminder)) {
            XCTAssertEqual($0 as? TaskSourceError, .notFound)
        }
    }

    func testDraftFillsANewReminder() {
        let reminder = reminder()
        ReminderMapper.fill(
            reminder,
            from: TaskDraft(title: "  Buy milk ", dueDate: date(2026, 9, 28, 10), hasDueTime: true, priority: .high, notes: "2L"),
            calendar: calendar
        )
        let result = item(reminder)
        XCTAssertEqual(result.title, "Buy milk")
        XCTAssertEqual(result.notes, "2L")
        XCTAssertEqual(result.priority, .high)
        XCTAssertEqual(result.dueDate, date(2026, 9, 28, 10))
        XCTAssertTrue(result.hasDueTime)
    }
}

extension ReminderMapperTests {
    /// What Reminders.app stores for "Monthly" on the 30th.
    func testRemindersMonthEndRuleReadsAsMonthlyAndKeepsTheExactRule() throws {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Faktura"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        reminder.dueDateComponents = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 9, day: 30, hour: 10)
        reminder.addRecurrenceRule(EKRecurrenceRule(
            recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [28, 29, 30],
            monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: [-1], end: nil
        ))
        let item = ReminderMapper.taskItem(from: reminder, calendar: calendar)
        XCTAssertEqual(item.recurrence, .monthly)
        let rule = try XCTUnwrap(item.recurrenceRule)
        XCTAssertEqual(rule.daysOfMonth, [28, 29, 30])
        XCTAssertEqual(rule.setPositions, [-1])
        let february = calendar.date(from: DateComponents(year: 2027, month: 2, day: 28))!
        XCTAssertTrue(rule.occurs(on: february, startingAt: item.dueDate!, calendar: calendar))
    }
}

extension ReminderMapperTests {
    func testRecurrenceRulesRoundTripThroughEventKit() {
        let rules = [
            TaskRecurrenceRule(frequency: .monthly, daysOfMonth: [28, 29, 30], setPositions: [-1]),
            TaskRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [.init(weekday: 2), .init(weekday: 4)]),
            TaskRecurrenceRule(frequency: .monthly, weekdays: [.init(weekday: 3, ordinal: 2)]),
            TaskRecurrenceRule(frequency: .yearly, months: [9], occurrenceCount: 5)
        ]
        for rule in rules {
            XCTAssertEqual(ReminderMapper.rule(from: ReminderMapper.ekRule(from: rule)), rule, rule.summary)
        }
    }

    func testDraftWithRepeatAndAlertFillsANewReminder() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let due = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 10))!
        ReminderMapper.fill(reminder, from: TaskDraft(title: "Report", dueDate: due, hasDueTime: true,
                                                      recurrenceRule: TaskRecurrenceRule(frequency: .weekly),
                                                      alert: .relative(minutesBefore: 15)), calendar: .current)
        XCTAssertEqual(reminder.recurrenceRules?.first?.frequency, .weekly)
        XCTAssertEqual(reminder.alarms?.first?.relativeOffset, -900)
    }
}
