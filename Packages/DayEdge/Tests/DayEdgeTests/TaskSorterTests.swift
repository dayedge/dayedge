import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class TaskSorterTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()
    private lazy var today = calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!)

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    private func task(_ id: String, due: Int? = nil, priority: TaskPriority = .none,
                      created: Int? = nil, order: Int = 0) -> TaskItem {
        TaskItem(id: id, title: id, listID: "w", dueDate: due.map(day), priority: priority,
                 creationDate: created.map(day), sourceOrder: order)
    }

    private func ids(_ tasks: [TaskItem], _ mode: TaskSortMode, _ direction: TaskSortDirection = .ascending) -> [String] {
        TaskSorter.sort(tasks, mode: mode, direction: direction, today: today, calendar: calendar).map(\.id)
    }

    func testSmartIsUrgencyFirst() {
        let tasks = [task("undated"), task("upcoming", due: 4), task("high", priority: .high),
                     task("overdue", due: -2), task("today", due: 0)]
        XCTAssertEqual(ids(tasks, .smart), ["overdue", "today", "upcoming", "high", "undated"])
        XCTAssertEqual(ids(tasks, .smart, .descending), ids(tasks, .smart)) // no direction
    }

    func testDueDateKeepsUndatedLastInBothDirections() {
        let tasks = [task("none"), task("late", due: 9), task("soon", due: 1)]
        XCTAssertEqual(ids(tasks, .dueDate), ["soon", "late", "none"])
        XCTAssertEqual(ids(tasks, .dueDate, .descending), ["late", "soon", "none"])
    }

    func testPriorityFollowsAppleMeaningWithNoneLast() {
        let tasks = [task("none"), task("low", priority: .low), task("high", priority: .high), task("medium", priority: .medium)]
        XCTAssertEqual(ids(tasks, .priority), ["high", "medium", "low", "none"]) // highest first
        XCTAssertEqual(ids(tasks, .priority, .descending), ["low", "medium", "high", "none"])
    }

    func testTitleIsLocalizedAndDirectional() {
        let tasks = [task("banana"), task("Apple"), task("item 10"), task("item 2")]
        XCTAssertEqual(ids(tasks, .title), ["Apple", "banana", "item 2", "item 10"])
        XCTAssertEqual(ids(tasks, .title, .descending), ["item 10", "item 2", "banana", "Apple"])
    }

    func testCreatedPutsUnknownDatesLast() {
        let tasks = [task("unknown"), task("new", created: -1), task("old", created: -30)]
        XCTAssertEqual(ids(tasks, .created), ["old", "new", "unknown"])
        XCTAssertEqual(ids(tasks, .created, .descending), ["new", "old", "unknown"])
    }

    func testRemindersOrderUsesSourceOrder() {
        let tasks = [task("c", order: 2), task("a", order: 0), task("b", order: 1)]
        XCTAssertEqual(ids(tasks, .remindersOrder), ["a", "b", "c"])
        XCTAssertEqual(ids(tasks, .remindersOrder, .descending), ["c", "b", "a"])
    }

    func testTiesAreStableAcrossRuns() {
        let tasks = (0..<30).map { task("t\($0)", priority: .medium, order: 30 - $0) }
        let first = ids(tasks.shuffled(), .priority)
        for _ in 0..<5 { XCTAssertEqual(ids(tasks.shuffled(), .priority), first) }
        XCTAssertEqual(first.first, "t29") // ties fall back to source order
    }

    func testDirectionTitlesArePlainLanguage() {
        XCTAssertEqual(TaskSortMode.dueDate.directionTitle(.ascending), "Soonest First")
        XCTAssertEqual(TaskSortMode.priority.directionTitle(.ascending), "Highest First")
        XCTAssertEqual(TaskSortMode.title.directionTitle(.descending), "Z to A")
        XCTAssertFalse(TaskSortMode.smart.hasDirection)
    }

    func testSortAppliesToListsButNotToAttentionOrCompleted() {
        let lists = [CalendarSource(id: "w", title: "Work", tint: .blue)]
        let now = calendar.date(byAdding: .hour, value: 12, to: today)!
        var done1 = task("done-old", order: 0); done1.isCompleted = true; done1.completionDate = day(-5)
        var done2 = task("done-new", order: 1); done2.isCompleted = true; done2.completionDate = day(-1)
        let tasks = [task("zulu", due: 5), task("alpha", due: 9), task("urgent-b", due: -1), task("urgent-a", due: -3), done1, done2]
        var options = TaskBucketOptions()
        options.sortMode = .title
        options.completedExpanded = true
        let result = TaskBuckets.sections(tasks: tasks, lists: lists, now: now, calendar: calendar, options: options)
        XCTAssertEqual(result.first { $0.kind == .list("w") }?.tasks.map(\.id), ["alpha", "zulu"]) // sorted by title
        XCTAssertEqual(result.first { $0.kind == .needsAttention }?.tasks.map(\.id), ["urgent-a", "urgent-b"]) // urgency kept
        XCTAssertEqual(result.first { $0.kind == .completed }?.tasks.map(\.id), ["done-new", "done-old"]) // recent first kept
    }

    func testPreviewReflectsTheSort() {
        let lists = [CalendarSource(id: "w", title: "Work", tint: .blue)]
        let tasks = (0..<10).map { task("t\($0)", due: 10 - $0) }
        var options = TaskBucketOptions()
        options.sortMode = .dueDate
        options.sortDirection = .descending
        let preview = TaskBuckets.sections(tasks: tasks, lists: lists, now: today, calendar: calendar, options: options)
            .first { $0.kind == .list("w") }
        XCTAssertEqual(preview?.tasks.first?.id, "t0") // latest due, before expanding
        XCTAssertEqual(preview?.tasks.count, 5)
    }
}

final class TaskSortLabelTests: XCTestCase {
    func testTriggerLabelsStayCompact() {
        XCTAssertEqual(TaskSortMode.smart.shortTitle, "Smart")
        XCTAssertEqual(TaskSortMode.remindersOrder.shortTitle, "Reminders")
        XCTAssertTrue(TaskSortMode.allCases.allSatisfy { $0.shortTitle.count <= 10 })
    }
}
