import SwiftUI
import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class TaskBucketsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 12))!
    private let lists = [
        CalendarSource(id: "w", title: "Work", tint: .blue),
        CalendarSource(id: "p", title: "Personal", tint: .green)
    ]

    private func day(_ offset: Int, hour: Int? = nil) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        return hour.map { calendar.date(byAdding: .hour, value: $0, to: base)! } ?? base
    }

    private func task(_ id: String, list: String = "w", due: Date? = nil, time: Bool = false,
                      priority: TaskPriority = .none, done: Bool = false, completedAt: Date? = nil) -> TaskItem {
        TaskItem(id: id, title: id, listID: list, dueDate: due, hasDueTime: time, priority: priority,
                 isCompleted: done, completionDate: completedAt)
    }

    private func sections(_ tasks: [TaskItem], _ options: TaskBucketOptions = .init(), lingering: Set<String> = []) -> [TaskSection] {
        TaskBuckets.sections(tasks: tasks, lists: lists, now: now, calendar: calendar, options: options, lingeringIDs: lingering)
    }

    private func ids(_ section: TaskSection?) -> [String] { section?.tasks.map(\.id) ?? [] }

    func testAttentionCollectsOverdueTodayAndHighPriority() {
        let result = sections([
            task("overdue", due: day(-2)), task("today", due: day(0)), task("high", priority: .high),
            task("tomorrow", due: day(1)), task("plain")
        ])
        let attention = result.first { $0.kind == .needsAttention }
        XCTAssertEqual(Set(ids(attention)), ["overdue", "today", "high"])
        XCTAssertEqual(ids(attention).first, "overdue") // most urgent first
    }

    func testEachTaskAppearsOnce() {
        let all = [task("a", due: day(-1)), task("b", list: "p", due: day(2)), task("c", priority: .high), task("d", list: "p")]
        let shown = sections(all).flatMap { $0.tasks.map(\.id) }
        XCTAssertEqual(shown.sorted(), ["a", "b", "c", "d"])
    }

    func testListSectionsFollowListOrderAndSkipEmpty() {
        XCTAssertEqual(sections([task("p1", list: "p", due: day(3)), task("w1", due: day(3))]).map(\.id), ["list-w", "list-p"])
        XCTAssertEqual(sections([task("p1", list: "p", due: day(3))]).map(\.id), ["list-p"])
    }

    // MARK: All Lists is a bounded overview

    // MARK: One document with bounded previews

    func testListPreviewsAreBoundedAndExpandable() {
        let many = (0..<20).map { task("w\($0)", due: day(3 + $0)) }
        let few = (0..<4).map { task("p\($0)", list: "p", due: day(3 + $0)) }
        let work = sections(many + few).first { $0.kind == .list("w") }
        XCTAssertEqual(work?.tasks.count, 5)
        XCTAssertEqual(work?.totalCount, 20)
        XCTAssertEqual(work?.hiddenCount, 15)
        XCTAssertEqual(work?.canExpand, true)
        XCTAssertEqual(work?.isExpanded, false)
        let personal = sections(many + few).first { $0.kind == .list("p") }
        XCTAssertEqual(personal?.tasks.count, 4) // ≤ 5 shows everything
        XCTAssertEqual(personal?.canExpand, false)
    }

    func testExpansionIsPerSection() {
        let work = (0..<20).map { task("w\($0)", due: day(3 + $0)) }
        let personal = (0..<20).map { task("p\($0)", list: "p", due: day(3 + $0)) }
        var options = TaskBucketOptions()
        options.expandedSectionIDs = ["list-w"]
        let result = sections(work + personal, options)
        XCTAssertEqual(result.first { $0.kind == .list("w") }?.tasks.count, 20)
        XCTAssertEqual(result.first { $0.kind == .list("w") }?.isExpanded, true)
        XCTAssertEqual(result.first { $0.kind == .list("p") }?.tasks.count, 5) // untouched
    }

    func testAttentionPreviewIsBoundedAndExpandable() {
        let overdue = (0..<10).map { task("o\($0)", due: day(-1 - $0)) }
        let attention = sections(overdue).first { $0.kind == .needsAttention }
        XCTAssertEqual(attention?.tasks.count, 6)
        XCTAssertEqual(attention?.totalCount, 10)
        XCTAssertEqual(attention?.canExpand, true)
        var options = TaskBucketOptions()
        options.expandedSectionIDs = ["attention"]
        XCTAssertEqual(sections(overdue, options).first?.tasks.count, 10)
    }

    func testDocumentOrderAndLandmarks() {
        let result = sections([
            task("a", due: day(-1)), task("w", due: day(2)), task("p", list: "p", due: day(2)),
            task("d", done: true, completedAt: day(-1))
        ])
        XCTAssertEqual(result.map(\.id), ["attention", "list-w", "list-p", "completed"])
        XCTAssertEqual(result.filter(\.isNavigable).map(\.id), ["attention", "list-w", "list-p", "completed"]) // Completed is a landmark, always last
        XCTAssertEqual(result.map(\.navigatorTitle), ["Attention", "Work", "Personal", "Completed"])
    }

    func testEmptyAttentionOmitsTheSection() {
        XCTAssertNil(sections([task("plain", due: day(5))]).first { $0.kind == .needsAttention })
    }

    // MARK: Ranking

    func testRankingPutsUrgentDatedTasksBeforeUndated() {
        let today = calendar.startOfDay(for: now)
        let ranked = TaskBuckets.ranked([
            task("undatedLow"), task("upcoming", due: day(4)), task("undatedMedium", priority: .medium),
            task("overdue", due: day(-3)), task("dueToday", due: day(0)), task("sooner", due: day(2))
        ], today: today, calendar: calendar).map(\.id)
        XCTAssertEqual(ranked, ["overdue", "dueToday", "sooner", "upcoming", "undatedMedium", "undatedLow"])
    }

    func testPreviewSurfacesDatedTasksNotUndatedOnes() {
        let undated = (0..<10).map { task("u\($0)") }
        let dated = task("dated", due: day(20))
        let work = sections(undated + [dated]).first { $0.kind == .list("w") }
        XCTAssertEqual(work?.tasks.first?.id, "dated")
    }

    // MARK: Completed / lingering / search / due text

    func testCompletedIsCollapsedByDefaultButCountsEverything() {
        let done = (0..<40).map { task("d\($0)", done: true, completedAt: day(-$0 - 1)) }
        let collapsed = sections(done).first { $0.kind == .completed }
        XCTAssertEqual(collapsed?.totalCount, 40) // an honest total, including old ones
        XCTAssertEqual(collapsed?.tasks.count, 0)
    }

    func testCompletedComesInBatchesNewestFirst() {
        var done = (0..<40).map { task("d\($0)", done: true, completedAt: day(-$0 - 1)) }
        done.append(task("nodate", done: true)) // no completion date: sorts last
        var options = TaskBucketOptions()
        options.completedExpanded = true
        let first = sections(done, options).first { $0.kind == .completed }
        XCTAssertEqual(first?.tasks.count, 15)
        XCTAssertEqual(first?.tasks.first?.id, "d0") // most recently completed first
        XCTAssertEqual(first?.hiddenCount, 26)
        options.completedLimit = 30
        XCTAssertEqual(sections(done, options).first { $0.kind == .completed }?.tasks.count, 30)
        options.completedLimit = 100
        XCTAssertEqual(sections(done, options).first { $0.kind == .completed }?.tasks.last?.id, "nodate")
    }

    func testCompletionText() {
        func text(_ offset: Int) -> String? {
            TaskBuckets.completionText(for: task("x", done: true, completedAt: offset == 99 ? nil : day(offset, hour: 9)), now: now, calendar: calendar)
        }
        XCTAssertEqual(text(0), "Today")
        XCTAssertEqual(text(-1), "Yesterday")
        XCTAssertNotNil(text(-5))
        XCTAssertNil(text(99))
    }

    func testLingeringTaskKeepsItsPreviousBucket() {
        let justDone = task("x", due: day(0), done: true, completedAt: now)
        XCTAssertNil(sections([justDone]).first { $0.kind == .needsAttention })
        let lingering = sections([justDone], lingering: ["x"])
        XCTAssertEqual(ids(lingering.first { $0.kind == .needsAttention }), ["x"])
        XCTAssertNil(lingering.first { $0.kind == .completed })
    }

    func testSearchIgnoresScopeAndPutsCompletedLast() {
        let tasks = [
            task("milk run", list: "p", due: day(2)),
            task("milk done", done: true, completedAt: day(-1)),
            task("unrelated")
        ]
        let results = TaskBuckets.searchResults(tasks: tasks, query: " milk ", now: now, calendar: calendar)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .results)
        XCTAssertEqual(ids(results.first), ["milk run", "milk done"])
        XCTAssertTrue(TaskBuckets.searchResults(tasks: tasks, query: "  ", now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(TaskBuckets.searchResults(tasks: tasks, query: "zzz", now: now, calendar: calendar).isEmpty)
    }

    func testDueText() {
        func text(_ t: TaskItem) -> TaskDueText? { TaskBuckets.dueText(for: t, now: now, calendar: calendar) }
        XCTAssertNil(text(task("n")))
        XCTAssertEqual(text(task("a", due: day(-2)))?.text, "Overdue 2 days")
        XCTAssertEqual(text(task("b", due: day(-1)))?.text, "Overdue 1 day")
        XCTAssertEqual(text(task("c", due: day(0, hour: 14), time: true)), TaskDueText(text: "Today 14:00", isOverdue: false))
        XCTAssertEqual(text(task("d", due: day(0, hour: 9), time: true))?.isOverdue, true)
        XCTAssertEqual(text(task("e", due: day(1, hour: 9), time: true))?.text, "Tomorrow 09:00")
        XCTAssertEqual(text(task("f", due: day(1)))?.text, "Tomorrow")
    }

    func testDueTextFollowsTheTimeFormat() {
        func text(_ t: TaskItem) -> String? {
            TaskBuckets.dueText(for: t, now: now, calendar: calendar, format: .twelveHour)?.text
        }
        XCTAssertEqual(text(task("c", due: day(0, hour: 14), time: true)), "Today 2:00pm")
        XCTAssertEqual(text(task("e", due: day(1, hour: 9), time: true)), "Tomorrow 9:00am")
    }
}
