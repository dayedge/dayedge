import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class TaskOccurrenceNavigationTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 8))!
    }()

    private func faktura() -> TaskItem {
        TaskItem(id: "f", title: "Faktura", listID: "l", dueDate: day(9, 30), recurrence: .monthly,
                 recurrenceRule: TaskRecurrenceRule(frequency: .monthly, daysOfMonth: [28, 29, 30], setPositions: [-1]))
    }

    private func adjacent(_ task: TaskItem, from: Date, _ direction: OccurrenceDirection) -> Date? {
        TaskOccurrenceNavigation.adjacentDay(for: task, from: from, direction: direction, now: now, calendar: calendar)
    }

    func testStepsThroughShownOccurrences() {
        let task = faktura()
        XCTAssertEqual(adjacent(task, from: day(9, 30), .next), day(10, 30))
        XCTAssertEqual(adjacent(task, from: day(10, 30), .next), day(11, 30))
        XCTAssertEqual(adjacent(task, from: day(1, 30, year: 2027), .next), day(2, 28, year: 2027))
        XCTAssertEqual(adjacent(task, from: day(11, 30), .previous), day(10, 30))
        XCTAssertEqual(adjacent(task, from: day(10, 30), .previous), day(9, 30))
    }

    func testNothingBeforeTheCurrentOccurrence() {
        XCTAssertNil(adjacent(faktura(), from: day(9, 30), .previous), "history isn't shown, so there's no previous")
    }

    func testOverdueTaskIsCurrentOnToday() {
        let overdue = TaskItem(id: "p", title: "Pills", listID: "l", dueDate: day(9, 20), recurrence: .weekly)
        XCTAssertEqual(TaskOccurrenceNavigation.shownDay(of: overdue, now: now, calendar: calendar), day(9, 26))
        XCTAssertEqual(adjacent(overdue, from: day(9, 26), .next), day(9, 27), "next weekly day after today (a Sunday, like the 20th)")
        XCTAssertEqual(adjacent(overdue, from: day(9, 27), .previous), day(9, 26))
    }

    func testNonRepeatingOrCompletedHaveNoOccurrences() {
        let single = TaskItem(id: "s", title: "S", listID: "l", dueDate: day(9, 30))
        XCTAssertNil(adjacent(single, from: day(9, 30), .next))
        var done = faktura()
        done.isCompleted = true
        XCTAssertNil(adjacent(done, from: day(9, 30), .next))
    }

    func testRuleEndingIsRespectedWithinTheHorizon() {
        let ending = TaskItem(id: "e", title: "E", listID: "l", dueDate: day(9, 30), recurrence: .custom("x"),
                              recurrenceRule: TaskRecurrenceRule(frequency: .monthly, endDate: day(10, 31)))
        XCTAssertEqual(adjacent(ending, from: day(9, 30), .next), day(10, 30))
        XCTAssertNil(adjacent(ending, from: day(10, 30), .next))
    }

    func testCalendarMenuOffersOccurrenceNavigationOnlyForRepeatingTasks() {
        let entries = TaskContextMenuPlan.entries(for: faktura(), context: .calendar)
        let next = try? XCTUnwrap(entries.firstIndex(of: .action(.nextOccurrence)))
        XCTAssertEqual(next.map { Array(entries[$0...($0 + 1)]) }, [.action(.nextOccurrence), .action(.previousOccurrence)],
                       "next first, as for events")
        XCTAssertEqual(TaskContextMenuPlan.title(for: .previousOccurrence), "Go to Previous Occurrence")
        XCTAssertEqual(TaskContextMenuPlan.title(for: .nextOccurrence), "Go to Next Occurrence")
        let single = TaskItem(id: "s", title: "S", listID: "l", dueDate: day(9, 30))
        XCTAssertFalse(TaskContextMenuPlan.entries(for: single, context: .calendar).contains(.action(.nextOccurrence)))
        XCTAssertFalse(TaskContextMenuPlan.entries(for: faktura()).contains(.action(.nextOccurrence)), "not in the Tasks view")
        XCTAssertTrue(TaskContextMenuPlan.entries(for: faktura(), isReadOnly: true, context: .calendar).contains(.action(.previousOccurrence)))
    }

    func testTasksViewOffersShowInCalendarForScheduledOpenTasks() {
        XCTAssertTrue(TaskContextMenuPlan.entries(for: faktura()).contains(.action(.showInCalendar)))
        XCTAssertEqual(TaskContextMenuPlan.title(for: .showInCalendar), "Show in Calendar")
        XCTAssertFalse(TaskContextMenuPlan.entries(for: TaskItem(id: "n", title: "N", listID: "l")).contains(.action(.showInCalendar)))
        XCTAssertFalse(TaskContextMenuPlan.entries(for: faktura(), context: .calendar).contains(.action(.showInCalendar)))
    }
}
