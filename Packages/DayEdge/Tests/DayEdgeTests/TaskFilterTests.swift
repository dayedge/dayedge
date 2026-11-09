import XCTest
@testable import Domain
@testable import UI

final class TaskFilterTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 12))!
    private lazy var today = calendar.startOfDay(for: now)
    private let lists = [
        CalendarSource(id: "w", title: "Work", tint: .blue),
        CalendarSource(id: "p", title: "Personal", tint: .green)
    ]

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    private func task(_ id: String, list: String = "w", due: Date? = nil, priority: TaskPriority = .none,
                      done: Bool = false) -> TaskItem {
        TaskItem(id: id, title: id, listID: list, dueDate: due, priority: priority, isCompleted: done)
    }

    private func shown(_ filter: TaskFilter, _ tasks: [TaskItem]) -> Set<String> {
        Set(tasks.filter { filter.includes($0, isCompleted: $0.isCompleted, today: today, calendar: calendar) }.map(\.id))
    }

    private func sections(_ filter: TaskFilter, _ tasks: [TaskItem]) -> [TaskSection] {
        TaskBuckets.sections(tasks: tasks.filter { filter.includes($0, isCompleted: $0.isCompleted, today: today, calendar: calendar) },
                             lists: lists, now: now, calendar: calendar, options: filter.options(from: .init()))
    }

    func testTodayHoldsOverdueAndDueToday() {
        let tasks = [task("overdue", due: day(-3)), task("today", due: day(0)), task("tomorrow", due: day(1)), task("undated")]
        XCTAssertEqual(shown(.today, tasks), ["overdue", "today"])
    }

    func testNextWeekEndsOnTheSixthDayAhead() {
        XCTAssertEqual(shown(.nextWeek, [task("sixth", due: day(6)), task("seventh", due: day(7))]), ["sixth"])
    }

    func testNextWeekHoldsOverdue() {
        XCTAssertEqual(shown(.nextWeek, [task("overdue", due: day(-10))]), ["overdue"])
    }

    func testNarrowFiltersLeaveCompletedTasksOut() {
        let tasks = [task("done", due: day(0), done: true)]
        XCTAssertTrue(shown(.today, tasks).isEmpty)
        XCTAssertTrue(shown(.nextWeek, tasks).isEmpty)
    }

    func testAJustTickedTaskStaysInItsFilter() {
        let ticked = task("ticked", due: day(0), done: true)
        XCTAssertTrue(TaskFilter.today.includes(ticked, isCompleted: false, today: today, calendar: calendar))
    }

    func testAllTasksKeepsTheDocumentOptions() {
        let base = TaskBucketOptions(expandedSectionIDs: ["list-w"], completedLimit: 30)
        XCTAssertEqual(TaskFilter.all.options(from: base), base)
    }

    func testTodayIsGroupedByListWithoutNeedsAttention() {
        let tasks = [task("high", list: "p", due: day(0), priority: .high), task("plain", due: day(0))]
        XCTAssertEqual(sections(.today, tasks).map(\.id), ["list-w", "list-p"])
    }

    func testTodayShowsAListInFull() {
        let tasks = (0..<8).map { task("t\($0)", due: day(0)) }
        XCTAssertEqual(sections(.today, tasks).first?.tasks.count, 8)
    }

    func testTodayHasNoCompletedSection() {
        let tasks = [task("done", due: day(0), done: true), task("open", due: day(0))]
        XCTAssertFalse(sections(.today, tasks).contains { $0.id == "completed" })
    }

    func testCountsMatchWhatEachFilterHolds() {
        let tasks = [task("a", due: day(0)), task("b", list: "p", due: day(3)), task("c", list: "p"), task("d", done: true)]
        XCTAssertEqual(TaskFilter.counts(tasks: tasks, now: now, calendar: calendar), [.today: 1, .nextWeek: 2, .all: 3])
    }

    func testNeedsAttentionPicksNoFilter() {
        XCTAssertNil(TaskSmartView.attention.filter)
        XCTAssertEqual(TaskSmartView.today.filter, .today)
    }
}
