import XCTest
@testable import Shell
@testable import Domain
@testable import UI
@testable import Agenda

final class ScheduledTaskIndexTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int? = nil) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour ?? 0))!
    }

    private func task(_ id: String, day: Int?, hour: Int? = nil, done: Bool = false, priority: TaskPriority = .none, order: Int = 0) -> TaskItem {
        TaskItem(id: id, title: id, listID: "l", dueDate: day.map { date($0, hour) }, hasDueTime: hour != nil,
                 priority: priority, isCompleted: done, sourceOrder: order)
    }

    private var now: Date { date(26, 8) }

    func testBucketsByDayAndKindWithOverdueOnTodayOnly() {
        let index = ScheduledTaskIndex(tasks: [
            task("old", day: 24), task("yesterdayTimed", day: 25, hour: 16),
            task("today", day: 26), task("todayAt14", day: 26, hour: 14), task("todayAt9", day: 26, hour: 9),
            task("future", day: 28), task("noDate", day: nil), task("done", day: 26, done: true)
        ], now: now, calendar: calendar, signature: 1)

        let today = index.tasks(on: date(26, 12), calendar: calendar)
        XCTAssertEqual(today.overdue.map(\.id), ["old", "yesterdayTimed"])
        XCTAssertEqual(today.untimed.map(\.id), ["today"])
        XCTAssertEqual(today.timed.map(\.id), ["todayAt9", "todayAt14"])
        XCTAssertEqual(today.count, 5)

        XCTAssertTrue(index.tasks(on: date(24), calendar: calendar).isEmpty, "overdue never shows on past days")
        XCTAssertEqual(index.tasks(on: date(28), calendar: calendar).untimed.map(\.id), ["future"])
        XCTAssertEqual(index.tasks(on: date(28), calendar: calendar).overdue, [])
    }

    func testUntimedOrderIsPriorityThenSourceOrder() {
        let index = ScheduledTaskIndex(tasks: [
            task("b", day: 26, order: 2), task("a", day: 26, order: 1), task("high", day: 26, priority: .high, order: 9)
        ], now: now, calendar: calendar, signature: 1)
        XCTAssertEqual(index.tasks(on: now, calendar: calendar).untimed.map(\.id), ["high", "a", "b"])
    }

    func testEqualityIsTheSignature() {
        let a = ScheduledTaskIndex(tasks: [task("x", day: 26)], now: now, calendar: calendar, signature: 7)
        let b = ScheduledTaskIndex(tasks: [], now: now, calendar: calendar, signature: 7)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, .empty)
        XCTAssertTrue(ScheduledTaskIndex.empty.tasks(on: now).isEmpty)
    }

    func testNowTargetGapEndsAtACloserTask() {
        let event = AgendaEventModel(id: "E", startTime: "10:30", endTime: "11:00",
                                     startDate: date(26, 10).addingTimeInterval(1800), endDate: date(26, 11), title: "E")
        let target = preferredNowTarget(
            on: date(26), events: [event], timedTasks: [task("T", day: 26, hour: 9)],
            now: date(26, 8), calendar: calendar
        )
        XCTAssertEqual(target, .gap(nextItemID: AgendaItemID.task("T"), until: date(26, 9)))
        XCTAssertEqual(
            preferredNowTarget(on: date(26), events: [], timedTasks: [task("T", day: 26, hour: 9)], now: date(26, 10), calendar: calendar),
            .endOfDay
        )
        XCTAssertEqual(preferredNowTarget(on: date(26), events: [], now: date(26, 10), calendar: calendar), .day)
    }

    func testLabelsAndSuccessor() {
        XCTAssertEqual(DayCountLabel.text(events: 1, tasks: 5), "1 event · 5 tasks")
        XCTAssertEqual(DayCountLabel.text(events: 0, tasks: 1), "1 task")
        XCTAssertNil(DayCountLabel.text(events: 0, tasks: 0))

        XCTAssertEqual(SelectionSuccessor.after(removing: "a", in: ["a", "b", "c"]), "b")
        XCTAssertEqual(SelectionSuccessor.after(removing: "c", in: ["a", "b", "c"]), "b")
        XCTAssertNil(SelectionSuccessor.after(removing: "a", in: ["a"]))
    }
}

final class DayTaskLayoutTests: XCTestCase {
    private var calendar: Calendar { .autoupdatingCurrent }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: hour, minute: minute))!
    }

    private func task(_ id: String, at hour: Int?, minute: Int = 0) -> TaskItem {
        TaskItem(id: id, title: id, listID: "l", dueDate: hour.map { date($0, minute) } ?? date(0), hasDueTime: hour != nil)
    }

    func testCardsPutTheRingOnTheDueMinuteAndStackOnCollision() {
        let markers = DayTaskMarkerLayout.layout(
            tasks: [task("b", at: 14, minute: 10), task("a", at: 14), task("c", at: 16), task("untimed", at: nil)],
            minuteHeight: 1, gap: 2, ringCenter: 15, calendar: calendar
        ) { _ in 48 }
        XCTAssertEqual(markers.map(\.task.id), ["a", "b", "c"])
        XCTAssertEqual(markers[0].anchorY, 840)
        XCTAssertEqual(markers[0].y, 825, "ring center (15pt down) lies on 14:00")
        XCTAssertEqual(markers[1].y, 875, "stacked right below the first card")
        XCTAssertEqual(markers[2].y, 945, "far enough away to stay anchored")
        XCTAssertEqual(markers[0].span(minuteHeight: 1), DayTimelineLayout.TaskSpan(id: "a", startMinutes: 825, endMinutes: 873))
    }

    func testEachCardStacksByItsOwnHeight() {
        let tall = TimedTaskCardMetrics.height(hasSecondLine: true)
        let short = TimedTaskCardMetrics.height(hasSecondLine: false)
        let markers = DayTaskMarkerLayout.layout(
            tasks: [task("titleOnly", at: 10), task("withList", at: 10), task("third", at: 10)],
            minuteHeight: 1, gap: 2, ringCenter: AppTheme.Tasks.timelineCardRingCenter, calendar: calendar
        ) { $0.id == "withList" ? tall : short }

        XCTAssertEqual(markers.map(\.y), [600 - 16, 600 - 16 + short + 2, 600 - 16 + short + 2 + tall + 2],
                       "the first ring on 10:00; the rest stacked right below, no overlap, 2pt apart")
        XCTAssertEqual(markers.map(\.anchorY), [600, 600, 600], "every card still belongs to 10:00")
        XCTAssertEqual(markers[1].span(minuteHeight: 1).endMinutes - markers[1].span(minuteHeight: 1).startMinutes, Int(tall.rounded(.up)),
                       "collisions see the card's real height")
    }

    func testTaskCardsShareTheLaneWithEventsWithoutOverlapping() {
        let meeting = AgendaEventModel(id: "meeting", startTime: "14:00", endTime: "15:00", title: "m")
        let later = AgendaEventModel(id: "later", startTime: "18:00", endTime: "19:00", title: "l")
        let spans = [DayTimelineLayout.TaskSpan(id: "a", startMinutes: 825, endMinutes: 873),
                     DayTimelineLayout.TaskSpan(id: "b", startMinutes: 875, endMinutes: 923),
                     DayTimelineLayout.TaskSpan(id: "alone", startMinutes: 600, endMinutes: 648)]
        let lane = DayTimelineLayout.layout(events: [meeting, later], tasks: spans, day: date(0), calendar: calendar)

        XCTAssertEqual(lane.tasks["a"], .init(columnIndex: 0, columnCount: 2), "task first, next to its time")
        XCTAssertEqual(lane.tasks["b"], .init(columnIndex: 0, columnCount: 2), "stacked in the same column")
        let meetingColumn = lane.events.first { $0.event.id == "meeting" }
        XCTAssertEqual(meetingColumn?.columnIndex, 1)
        XCTAssertEqual(lane.tasks["alone"], .init(columnIndex: 0, columnCount: 1))
        XCTAssertEqual(lane.events.first { $0.event.id == "later" }?.columnCount, 1, "unrelated events keep full width")
    }

    func testDayKeyboardOrderIsOneSequence() {
        let events = [
            AgendaEventModel(id: "allDay", title: "Offsite"),
            AgendaEventModel(id: "morning", startTime: "08:30", endTime: "09:00", title: "m"),
            AgendaEventModel(id: "afternoon", startTime: "15:00", endTime: "16:00", title: "a")
        ]
        let section = AgendaDaySection(date: date(0), events: events)
        let tasks = DayTasks(overdue: [task("late", at: nil)], untimed: [task("milk", at: nil)], timed: [task("call", at: 14)])
        let order = AgendaSectionProjection.dayItemAnchors(section: section, tasks: tasks)
        XCTAssertEqual(order, [
            .event(sectionID: section.id, eventID: "allDay"),
            .task(sectionID: section.id, taskID: "late"),
            .task(sectionID: section.id, taskID: "milk"),
            .event(sectionID: section.id, eventID: "morning"),
            .task(sectionID: section.id, taskID: "call"),
            .event(sectionID: section.id, eventID: "afternoon")
        ])
    }
}

final class RecurringTaskProjectionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int? = nil, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour ?? 0))!
    }

    private func index(_ tasks: [TaskItem], now: Date? = nil) -> ScheduledTaskIndex {
        ScheduledTaskIndex(tasks: tasks, now: now ?? date(9, 26, 8), calendar: calendar, signature: 1)
    }

    private func task(_ id: String, due: Date, time: Bool = false, _ recurrence: TaskRecurrence) -> TaskItem {
        TaskItem(id: id, title: id, listID: "l", dueDate: due, hasDueTime: time, recurrence: recurrence)
    }

    private func ids(on day: Date, _ index: ScheduledTaskIndex) -> [String] {
        let tasks = index.tasks(on: day, calendar: calendar)
        return (tasks.allUntimed + tasks.timed).map(\.id)
    }

    func testMonthlyTaskShowsOnLaterMonths() {
        let index = index([task("invoice", due: date(9, 30), .monthly)])
        XCTAssertEqual(ids(on: date(9, 30), index), ["invoice"])
        XCTAssertEqual(ids(on: date(10, 30), index), ["invoice"])
        XCTAssertEqual(ids(on: date(11, 30), index), ["invoice"])
        XCTAssertEqual(ids(on: date(10, 29), index), [])
        XCTAssertEqual(ids(on: date(2, 28, year: 2027), index), [], "no 30th in February: skipped, like EventKit")
        XCTAssertTrue(index.tasks(on: date(10, 30), calendar: calendar).projectedIDs.contains("invoice"))
        XCTAssertFalse(index.tasks(on: date(9, 30), calendar: calendar).projectedIDs.contains("invoice"))
    }

    func testProjectedTimedOccurrenceKeepsItsTime() {
        let index = index([task("standup", due: date(9, 28, 9), time: true, .weekly)])
        let october5 = index.tasks(on: date(10, 5), calendar: calendar)
        XCTAssertEqual(october5.timed.first?.dueDate, date(10, 5, 9))
        XCTAssertEqual(ids(on: date(10, 6), index), [])
    }

    func testEachStandardRule() {
        let index = index([
            task("daily", due: date(9, 28), .daily),
            task("weekdays", due: date(9, 28), .weekdays),   // Monday
            task("biweekly", due: date(9, 28), .biweekly),
            task("yearly", due: date(9, 28), .yearly),
            task("custom", due: date(9, 28), .custom("Every 3 months"))
        ])
        XCTAssertEqual(Set(ids(on: date(10, 3), index)), ["daily"])                    // Saturday
        XCTAssertEqual(Set(ids(on: date(10, 5), index)), ["daily", "weekdays"])
        XCTAssertEqual(Set(ids(on: date(10, 12), index)), ["daily", "weekdays", "biweekly"])
        XCTAssertTrue(ids(on: date(9, 28, year: 2027), index).contains("yearly"))
        XCTAssertFalse(ids(on: date(12, 28), index).contains("custom"), "a rule we can't read isn't guessed")
    }

    func testOverdueRepeatingTaskIsNotDuplicatedOnTodayOrThePast() {
        let index = index([task("pills", due: date(9, 24), .daily)])
        XCTAssertEqual(ids(on: date(9, 26), index), ["pills"], "shown once, as overdue")
        XCTAssertEqual(index.tasks(on: date(9, 26), calendar: calendar).overdue.map(\.id), ["pills"])
        XCTAssertEqual(ids(on: date(9, 25), index), [], "no occurrences in the past")
        XCTAssertEqual(ids(on: date(9, 27), index), ["pills"])
    }

    func testCompletedRepeatingTaskIsNotProjected() {
        var done = task("done", due: date(9, 30), .monthly)
        done.isCompleted = true
        XCTAssertEqual(ids(on: date(10, 30), index([done])), [])
    }
}
