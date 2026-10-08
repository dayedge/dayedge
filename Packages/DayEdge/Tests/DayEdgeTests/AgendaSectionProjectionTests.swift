import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

final class AgendaSectionProjectionTests: XCTestCase {
    // `AgendaSectionProjection`'s NOW-marker math reads wall-clock minutes
    // via `Calendar.autoupdatingCurrent` (matching the code it was
    // extracted from), so test dates are built against that same
    // calendar rather than a fixed UTC one — otherwise the two would
    // disagree by this machine's UTC offset.
    private var calendar: Calendar { .autoupdatingCurrent }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute))!
    }

    private func event(_ id: String, _ start: String, _ end: String) -> AgendaEventModel {
        AgendaEventModel(id: id, startTime: start, endTime: end, title: id)
    }

    private func section(_ events: [AgendaEventModel]) -> AgendaDaySection {
        AgendaDaySection(date: date(0), events: events)
    }

    private func rowIDs(_ rows: [AgendaSectionProjection.TimedRow]) -> [String] {
        rows.map { row in
            switch row.kind {
            case .event(let event, _): event.id
            case .task(let task, let overdue): overdue ? "!\(task.id)" : "T:\(task.id)"
            case .now: "NOW"
            }
        }
    }

    // MARK: - timedRows

    func testNoNowPresentationReturnsEventsInOrderWithoutMarker() {
        let events = [event("A", "09:00", "10:00"), event("B", "10:00", "11:00")]
        let rows = AgendaSectionProjection.rows(section: section(events), nowPresentation: nil)
        XCTAssertEqual(rowIDs(rows), ["A", "B"])
    }

    func testNoNowOrTimedTasksPreservesCompleteRowsAndIncomingOrder() {
        let allDay = AgendaEventModel(id: "all-day", title: "All day")
        let legacy = event("legacy", "15:00", "16:00")
        let multiDay = AgendaEventModel(id: "span", startTime: "09:00", endTime: "10:00",
                                       startDate: date(9).addingTimeInterval(-86400),
                                       endDate: date(10).addingTimeInterval(86400), title: "Multi-day",
                                       subtitle: "Keep subtitle", status: .tentative, isRecurring: true)
        let cancelled = AgendaEventModel(id: "cancelled", startTime: "08:00", endTime: "09:00",
                                        startDate: date(8), endDate: date(9), title: "Cancelled", status: .cancelled)
        let overdue = TaskItem(id: "overdue", title: "Overdue", notes: "Keep notes", listID: "l")
        let untimed = TaskItem(id: "untimed", title: "Untimed", listID: "l")
        let input = section([allDay, legacy, multiDay, cancelled])
        let rows = AgendaSectionProjection.rows(section: input,
            tasks: DayTasks(overdue: [overdue], untimed: [untimed]), nowPresentation: nil)
        XCTAssertEqual(rowIDs(rows), ["!overdue", "T:untimed", "legacy", "span", "cancelled"])
        XCTAssertEqual(rows.map(\.id), [
            .task(sectionID: input.id, taskID: overdue.id), .task(sectionID: input.id, taskID: untimed.id),
            .event(sectionID: input.id, eventID: legacy.id), .event(sectionID: input.id, eventID: multiDay.id),
            .event(sectionID: input.id, eventID: cancelled.id)
        ])
        for (row, task) in zip(rows.prefix(2), [overdue, untimed]) {
            guard case .task(let value, let isOverdue) = row.kind else { return XCTFail("expected task") }
            XCTAssertEqual(value, task)
            XCTAssertEqual(isOverdue, task.id == overdue.id)
        }
        for (row, expected) in zip(rows.dropFirst(2), [legacy, multiDay, cancelled]) {
            guard case .event(let value, let isOngoing) = row.kind else { return XCTFail("expected event") }
            XCTAssertEqual(value, expected)
            XCTAssertFalse(isOngoing)
        }
    }

    func testGapInsertsMarkerBeforeNextEvent() {
        let events = [event("A", "09:00", "10:00"), event("B", "11:00", "12:00")]
        let presentation = AgendaNowPresentation(day: date(0), minute: date(10, 30), target: .gap(nextItemID: "B", until: date(11)))
        let rows = AgendaSectionProjection.rows(section: section(events), nowPresentation: presentation)
        XCTAssertEqual(rowIDs(rows), ["A", "NOW", "B"])
    }

    func testGapWithNoNextEventAppendsMarkerAtEnd() {
        let events = [event("A", "09:00", "10:00")]
        let presentation = AgendaNowPresentation(day: date(0), minute: date(10, 30), target: .gap(nextItemID: nil, until: nil))
        let rows = AgendaSectionProjection.rows(section: section(events), nowPresentation: presentation)
        XCTAssertEqual(rowIDs(rows), ["A", "NOW"])
    }

    func testOngoingGroupsPastMarkerActiveThenFuture() {
        let events = [
            event("Past", "08:00", "09:00"),
            event("Active", "09:30", "10:30"),
            event("Future", "11:00", "12:00")
        ]
        let presentation = AgendaNowPresentation(day: date(0), minute: date(10, 0), target: .ongoing(eventIDs: ["Active"]))
        let rows = AgendaSectionProjection.rows(section: section(events), nowPresentation: presentation)
        XCTAssertEqual(rowIDs(rows), ["Past", "NOW", "Active", "Future"])

        guard case .event(_, let isOngoing) = rows[2].kind else { return XCTFail("expected the active row") }
        XCTAssertTrue(isOngoing)
        guard case .event(_, let pastIsOngoing) = rows[0].kind else { return XCTFail("expected the past row") }
        XCTAssertFalse(pastIsOngoing)
    }

    func testEndOfDayAppendsMarkerAfterAllEvents() {
        let events = [event("A", "09:00", "10:00")]
        let presentation = AgendaNowPresentation(day: date(0), minute: date(18, 0), target: .endOfDay)
        let rows = AgendaSectionProjection.rows(section: section(events), nowPresentation: presentation)
        XCTAssertEqual(rowIDs(rows), ["A", "NOW"])
    }

    func testDayTargetShowsNoMarker() {
        let events = [event("A", "09:00", "10:00")]
        let presentation = AgendaNowPresentation(day: date(0), minute: date(6, 0), target: .day)
        let rows = AgendaSectionProjection.rows(section: section(events), nowPresentation: presentation)
        XCTAssertEqual(rowIDs(rows), ["A"])
    }

    // MARK: - anchor(for:in:nowPresentation:)

    func testAnchorForGapPrecedingFirstEventTargetsDayHeader() {
        let events = [event("A", "09:00", "10:00")]
        let target = AgendaScrollTarget(date: date(0), nowTarget: .gap(nextItemID: "A", until: date(9)))
        let anchor = AgendaSectionProjection.anchor(for: target, in: [section(events)], nowPresentation: nil)
        XCTAssertEqual(anchor, .day(date(0)))
    }

    func testAnchorForGapAfterFirstEventTargetsNowMarker() {
        let events = [event("A", "09:00", "10:00"), event("B", "11:00", "12:00")]
        let target = AgendaScrollTarget(date: date(0), nowTarget: .gap(nextItemID: "B", until: date(11)))
        let anchor = AgendaSectionProjection.anchor(for: target, in: [section(events)], nowPresentation: nil)
        XCTAssertEqual(anchor, .now(sectionID: date(0)))
    }

    func testAnchorForOngoingWithPastRowsTargetsNowMarker() {
        let events = [event("Past", "08:00", "09:00"), event("Active", "09:30", "10:30")]
        let target = AgendaScrollTarget(date: date(0), nowTarget: .ongoing(eventIDs: ["Active"]))
        let presentation = AgendaNowPresentation(day: date(0), minute: date(10, 0), target: .ongoing(eventIDs: ["Active"]))
        let anchor = AgendaSectionProjection.anchor(for: target, in: [section(events)], nowPresentation: presentation)
        XCTAssertEqual(anchor, .now(sectionID: date(0)))
    }

    func testAnchorForOngoingWithNoPastRowsTargetsDayHeader() {
        let events = [event("Active", "09:30", "10:30")]
        let target = AgendaScrollTarget(date: date(0), nowTarget: .ongoing(eventIDs: ["Active"]))
        let presentation = AgendaNowPresentation(day: date(0), minute: date(10, 0), target: .ongoing(eventIDs: ["Active"]))
        let anchor = AgendaSectionProjection.anchor(for: target, in: [section(events)], nowPresentation: presentation)
        XCTAssertEqual(anchor, .day(date(0)))
    }

    func testAnchorForEndOfDayTargetsNowMarker() {
        let target = AgendaScrollTarget(date: date(0), nowTarget: .endOfDay)
        let anchor = AgendaSectionProjection.anchor(for: target, in: [section([])], nowPresentation: nil)
        XCTAssertEqual(anchor, .now(sectionID: date(0)))
    }

    func testAnchorForSpecificEventIDTargetsThatEvent() {
        let events = [event("A", "09:00", "10:00")]
        let target = AgendaScrollTarget(date: date(0), eventID: "A")
        let anchor = AgendaSectionProjection.anchor(for: target, in: [section(events)], nowPresentation: nil)
        XCTAssertEqual(anchor, .event(sectionID: date(0), eventID: "A"))
    }

    func testAnchorWithNoMatchingSectionReturnsNil() {
        let target = AgendaScrollTarget(date: date(0))
        let anchor = AgendaSectionProjection.anchor(for: target, in: [], nowPresentation: nil)
        XCTAssertNil(anchor)
    }
}

// MARK: - Tasks in the agenda

final class AgendaSectionTaskRowsTests: XCTestCase {
    private var calendar: Calendar { .autoupdatingCurrent }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 21) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func event(_ id: String, _ start: String, _ end: String) -> AgendaEventModel {
        AgendaEventModel(id: id, startTime: start, endTime: end, title: id)
    }

    private func task(_ id: String, at hour: Int? = nil, minute: Int = 0) -> TaskItem {
        TaskItem(id: id, title: id, listID: "l", dueDate: hour.map { date($0, minute) } ?? date(0), hasDueTime: hour != nil)
    }

    private func section(_ events: [AgendaEventModel]) -> AgendaDaySection {
        AgendaDaySection(date: date(0), events: events)
    }

    private func ids(_ rows: [AgendaSectionProjection.TimedRow]) -> [String] {
        rows.map { row in
            switch row.kind {
            case .event(let event, _): event.id
            case .task(let task, let overdue): overdue ? "!\(task.id)" : "T:\(task.id)"
            case .now: "NOW"
            }
        }
    }

    func testTodayOrderUntimedBeforeNowThenChronology() {
        let events = [event("Meeting", "10:30", "11:30"), event("Review", "13:00", "14:00")]
        let tasks = DayTasks(overdue: [task("Invoice")], untimed: [task("Milk")], timed: [task("Call", at: 12, minute: 15)])
        let presentation = AgendaNowPresentation(day: date(0), minute: date(8, 37), target: .gap(nextItemID: "Meeting", until: date(10, 30)))
        let rows = AgendaSectionProjection.rows(section: section(events), tasks: tasks, nowPresentation: presentation)
        XCTAssertEqual(ids(rows), ["!Invoice", "T:Milk", "NOW", "Meeting", "T:Call", "Review"])
    }

    func testOtherDayHasNoMarkerAndMergesTimedTasks() {
        let events = [event("A", "08:05", "09:35"), event("B", "14:00", "16:00")]
        let tasks = DayTasks(untimed: [task("Expense")], timed: [task("Bank", at: 12)])
        let rows = AgendaSectionProjection.rows(section: section(events), tasks: tasks, nowPresentation: nil)
        XCTAssertEqual(ids(rows), ["T:Expense", "A", "T:Bank", "B"])
    }

    func testEventComesBeforeTaskAtTheSameMinute() {
        let rows = AgendaSectionProjection.rows(
            section: section([event("E", "12:00", "13:00")]),
            tasks: DayTasks(timed: [task("T", at: 12)]), nowPresentation: nil
        )
        XCTAssertEqual(ids(rows), ["E", "T:T"])
    }

    func testGapCanEndAtATask() {
        let tasks = DayTasks(timed: [task("Soon", at: 9, minute: 15)])
        let presentation = AgendaNowPresentation(
            day: date(0), minute: date(8, 37),
            target: .gap(nextItemID: AgendaItemID.task("Soon"), until: date(9, 15))
        )
        let rows = AgendaSectionProjection.rows(section: section([event("Later", "10:30", "11:00")]), tasks: tasks, nowPresentation: presentation)
        XCTAssertEqual(ids(rows), ["NOW", "T:Soon", "Later"])
    }

    func testOngoingSplitsTasksByTheMarker() {
        let tasks = DayTasks(timed: [task("Early", at: 9), task("Late", at: 11)])
        let presentation = AgendaNowPresentation(day: date(0), minute: date(10), target: .ongoing(eventIDs: ["Active"]))
        let rows = AgendaSectionProjection.rows(section: section([event("Active", "09:30", "10:30")]), tasks: tasks, nowPresentation: presentation)
        XCTAssertEqual(ids(rows), ["T:Early", "NOW", "Active", "T:Late"])
    }

    func testTasksOnlyDay() {
        let rows = AgendaSectionProjection.rows(section: section([]), tasks: DayTasks(untimed: [task("A")], timed: [task("B", at: 9)]), nowPresentation: nil)
        XCTAssertEqual(ids(rows), ["T:A", "T:B"])
        XCTAssertEqual(AgendaSectionProjection.itemAnchors(in: rows).count, 2)
    }

    func testAnchorTargetsNowWhenUntimedTasksPrecedeIt() {
        let target = AgendaScrollTarget(date: date(0), nowTarget: .gap(nextItemID: "A", until: date(9)))
        let withoutTasks = AgendaSectionProjection.anchor(for: target, in: [section([event("A", "09:00", "10:00")])], nowPresentation: nil)
        XCTAssertEqual(withoutTasks, .day(date(0)))
        let withTasks = AgendaSectionProjection.anchor(
            for: target, in: [section([event("A", "09:00", "10:00")])], nowPresentation: nil,
            tasks: { _ in DayTasks(untimed: [self.task("Milk")]) }
        )
        XCTAssertEqual(withTasks, .now(sectionID: date(0)))
    }
}
