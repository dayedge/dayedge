import CalendarIndex
import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

final class TaskSearchTests: XCTestCase {
    private func task(_ title: String, notes: String? = nil) -> TaskItem {
        TaskItem(id: UUID().uuidString, title: title, notes: notes, listID: "l")
    }

    func testEveryWordMustMatchTitleOrNotesIgnoringCaseAndAccents() {
        XCTAssertTrue(TaskSearch.matches(task("Spotkanie zespołu"), query: "spotk"))
        XCTAssertTrue(TaskSearch.matches(task("Café order"), query: "CAFE"))
        XCTAssertTrue(TaskSearch.matches(task("Invoice", notes: "for ACME"), query: "invoice acme"))
        XCTAssertFalse(TaskSearch.matches(task("Invoice"), query: "invoice acme"))
        XCTAssertFalse(TaskSearch.matches(task("Invoice"), query: "  "))
    }
}

final class SearchIndexBuildTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_791_201_600)  // 2026-10-05 12:00 UTC

    private func at(_ dayOffset: Int, _ hour: Int? = nil) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))!
        return hour.map { calendar.date(byAdding: .hour, value: $0, to: day)! } ?? day
    }

    private func task(_ id: String, due: Date?, timed: Bool = false, done: Bool = false) -> TaskItem {
        TaskItem(id: id, title: id, listID: "l", dueDate: due, hasDueTime: timed, isCompleted: done)
    }

    func testAgendaOrderWithinADayDaysGroupedAndUndatedLast() {
        let index = SearchIndex.build(
            matches: [SearchMatch(id: 3, start: at(1, 9), isAllDay: false), SearchMatch(id: 2, start: at(1), isAllDay: true),
                      SearchMatch(id: 1, start: at(-3, 10), isAllDay: false)],
            tasks: [task("untimed", due: at(1)), task("timed", due: at(1, 9), timed: true),
                    task("nodate-done", due: nil, done: true), task("nodate", due: nil)],
            now: now, calendar: calendar)
        XCTAssertEqual(index.entries, [.event(id: 1, start: at(-3, 10), isAllDay: false),
                                       .event(id: 2, start: at(1), isAllDay: true), .task(task("untimed", due: at(1))),
                                       .event(id: 3, start: at(1, 9), isAllDay: false),
                                       .task(task("timed", due: at(1, 9), timed: true)),
                                       .task(task("nodate", due: nil)), .task(task("nodate-done", due: nil, done: true))])
        XCTAssertEqual(index.days.map(\.range), [0..<1, 1..<5, 5..<7])
        XCTAssertEqual(index.days[1].eventCount, 2)
        XCTAssertEqual(index.days[1].taskCount, 2)
        XCTAssertNil(index.days[2].day, "No Date group")
        XCTAssertEqual(index.anchorDayIndex, 1)
        XCTAssertEqual(index.dayIndex(containing: 4), 1)
        XCTAssertEqual(index.eventPositions[3], 3)
    }

    func testAllPastAnchorsOnTheLastDatedDay() {
        let index = SearchIndex.build(matches: [SearchMatch(id: 1, start: at(-9, 9), isAllDay: false),
                                                SearchMatch(id: 2, start: at(-2, 9), isAllDay: false)],
                                      tasks: [], now: now, calendar: calendar)
        XCTAssertEqual(index.anchorDayIndex, 1)
    }

    func testEventTiesKeepPaddedDecimalOrderIncludingSignedExtremes() {
        let ids: [Int64] = [Int64.max, -10, 10, Int64.min, -2, 2, -1, 0, 1]
        let index = SearchIndex.build(matches: ids.map {
            SearchMatch(id: $0, start: at(0, 9), isAllDay: false)
        }, tasks: [], now: now, calendar: calendar)
        XCTAssertEqual(index.entries.compactMap(\.eventID), [-1, -2, -10, Int64.min, 0, 1, 2, 10, Int64.max])
    }

    func testTaskConcatenationTiesStayStableAndEventsComeFirst() {
        let first = TaskItem(id: "c", title: "ab", listID: "l", dueDate: at(0, 9), hasDueTime: true)
        let second = TaskItem(id: "bc", title: "a", listID: "l", dueDate: at(0, 9), hasDueTime: true)
        let index = SearchIndex.build(matches: [SearchMatch(id: 1, start: at(0, 9), isAllDay: false)],
                                      tasks: [first, second], now: now, calendar: calendar)
        XCTAssertEqual(index.entries, [.event(id: 1, start: at(0, 9), isAllDay: false), .task(first), .task(second)])
    }

    func testDuplicateEventIDPositionPointsToLastOrderedOccurrence() {
        let index = SearchIndex.build(matches: [
            SearchMatch(id: 7, start: at(2, 9), isAllDay: false),
            SearchMatch(id: 7, start: at(-2, 9), isAllDay: false)
        ], tasks: [], now: now, calendar: calendar)
        XCTAssertEqual(index.total, 2)
        XCTAssertEqual(index.eventPositions[7], 1)
        XCTAssertEqual(index.days.map(\.range), [0..<1, 1..<2])
        XCTAssertEqual(index.anchorDayIndex, 1)
    }

    func testEmptyAndUndatedOnlyAnchorsAndTaskOrdering() {
        let open2 = task("Task 2", due: nil)
        let open10 = task("Task 10", due: nil)
        let completed = task("Task 1", due: nil, done: true)
        for anchorsAtStart in [false, true] {
            XCTAssertEqual(SearchIndex.build(matches: [], tasks: [], now: now, calendar: calendar,
                                              anchorsAtStart: anchorsAtStart), .empty)
            let index = SearchIndex.build(matches: [], tasks: [completed, open10, open2], now: now,
                                          calendar: calendar, anchorsAtStart: anchorsAtStart)
            XCTAssertEqual(index.entries, [.task(open2), .task(open10), .task(completed)])
            XCTAssertEqual(index.anchorDayIndex, 0)
            XCTAssertEqual(index.days, [.init(day: nil, range: 0..<3, eventCount: 0, taskCount: 3)])
        }
    }

    func testDSTDaysGroupByLocalDayAndKeepCountsAndAnchors() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        for (month, day) in [(3, 29), (10, 25)] {
            let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let next = calendar.date(byAdding: .day, value: 1, to: start)!
            let untimed = TaskItem(id: "untimed", title: "Untimed", listID: "l", dueDate: start)
            let index = SearchIndex.build(matches: [
                SearchMatch(id: 1, start: start, isAllDay: true),
                SearchMatch(id: 2, start: start.addingTimeInterval(3600), isAllDay: false),
                SearchMatch(id: 3, start: start.addingTimeInterval(3 * 3600), isAllDay: false),
                SearchMatch(id: 4, start: next, isAllDay: true)
            ], tasks: [untimed], now: next, calendar: calendar)
            XCTAssertEqual(index.days, [.init(day: start, range: 0..<4, eventCount: 3, taskCount: 1),
                                        .init(day: next, range: 4..<5, eventCount: 1, taskCount: 0)])
            XCTAssertEqual(index.entries[1], .task(untimed))
            XCTAssertEqual(index.anchorDayIndex, 1)
            XCTAssertEqual(SearchIndex.build(matches: [], tasks: [untimed], now: next, calendar: calendar,
                                             anchorsAtStart: true).anchorDayIndex, 0)
        }
    }
}

@MainActor
final class SearchSessionTests: XCTestCase {
    /// A session over `count` daily matches starting `startOffset` days from
    /// today; records what was loaded.
    private func session(count: Int, startOffset: Int = 0, loaded: LoadLog = LoadLog()) -> SearchSession {
        let session = SearchSession()
        session.debounce = .zero
        let base = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        session.searchMatches = { _ in
            (0..<count).map { SearchMatch(id: Int64($0), start: base.addingTimeInterval(Double(startOffset + $0) * 86400), isAllDay: false) }
        }
        session.loadEvents = { ids in
            loaded.batches.append(ids)
            return Dictionary(uniqueKeysWithValues: ids.map {
                ($0, AgendaEventModel(id: "e\($0)", startTime: "09:00", endTime: "10:00",
                                      startDate: base.addingTimeInterval(Double(startOffset + Int($0)) * 86400), title: "Daily \($0)"))
            })
        }
        return session
    }

    final class LoadLog { var batches: [[Int64]] = [] }

    func testExactTotalButOnlyTheOpeningWindowIsLoaded() async {
        let log = LoadLog()
        let session = session(count: 1000, loaded: log)
        session.update(query: "daily")
        await session.settle()
        XCTAssertEqual(session.total, 1000, "exact, not capped")
        XCTAssertEqual(session.preview.count, 3)
        XCTAssertEqual(session.events.count, SearchDayPaging.opening(at: 0, dayCount: 1000).count,
                       "only the days it opens on are in memory (today onward here), not all 1000")
    }

    func testTheRenderedDaysAreLoadedAndTheRestEvicted() async {
        let log = LoadLog()
        let session = session(count: 1000, loaded: log)
        session.update(query: "daily")
        await session.settle()
        session.show(days: 490..<520)
        await session.settle()
        XCTAssertEqual(session.events.count, 30 + 3, "the rendered days, plus the preview")
        session.show(days: 900..<930)
        await session.settle()
        XCTAssertNil(session.events[500], "paged away: evicted")
        XCTAssertNotNil(session.events[902])
        XCTAssertEqual(session.events.count, 33)
        let batches = log.batches.count
        session.show(days: 900..<930)
        await session.settle()
        XCTAssertEqual(log.batches.count, batches, "the same days: nothing loaded, nothing redrawn")
        session.show(days: 900..<940)
        await session.settle()
        XCTAssertEqual(log.batches.last, Array(930...939).map(Int64.init), "a page more: only its ids")
    }

    func testAllPastResultsFillThePreviewWithTheMostRecent() async {
        let session = session(count: 6, startOffset: -60)
        session.update(query: "past")
        await session.settle()
        XCTAssertEqual(session.preview.map(\.id), ["event:e3", "event:e4", "event:e5"])
    }

    func testShortQueriesDontSearch() async {
        let session = session(count: 10)
        session.update(query: "da")
        await session.settle()
        XCTAssertEqual(session.total, 0)
        XCTAssertFalse(SearchSession.isSearchable("da"))
        XCTAssertTrue(SearchSession.isSearchable("dai"))
    }

    func testStaleVisibleReportsAfterResultsShrinkAreHarmless() async {
        let session = session(count: 50)
        session.update(query: "daily")
        await session.settle()
        session.update(query: "da")  // under three letters: results cleared
        session.show(days: 30..<41)
        session.update(query: "dai")
        await session.settle()
        session.show(days: 200..<301)
        session.show(days: 45..<301)
        await session.settle()
        XCTAssertEqual(session.total, 50)
    }

    func testDelayedWindowResultsKeepOnlyCurrentWindowAndPreview() async {
        let session = session(count: 1000)
        session.update(query: "daily")
        await session.settle()
        let reads = DelayedWindowReads()
        session.loadEvents = { ids in await reads.load(ids) }
        session.show(days: 500..<506)
        await reads.waitForRequests(1)
        session.show(days: 900..<906)
        await reads.waitForRequests(2)
        reads.complete(1)
        reads.complete(0)
        await session.settle()

        XCTAssertEqual(Set(session.events.keys), Set((900...905).map(Int64.init) + [0, 1, 2]))
        XCTAssertEqual(session.preview.map(\.id), ["event:e0", "event:e1", "event:e2"])
        XCTAssertEqual(session.total, 1000)
    }

    func testReturningToAnInFlightWindowReusesItsRead() async {
        let session = session(count: 1000)
        session.update(query: "daily")
        await session.settle()
        let reads = DelayedWindowReads()
        session.loadEvents = { ids in await reads.load(ids) }
        session.show(days: 500..<506)
        await reads.waitForRequests(1)
        session.show(days: 900..<906)
        await reads.waitForRequests(2)
        session.show(days: 500..<506)
        reads.complete(1)
        reads.complete(0)
        await session.settle()

        XCTAssertEqual(reads.requestCount, 2, "returning to a pending window does not repeat its storage read")
        XCTAssertEqual(Set(session.events.keys), Set((500...505).map(Int64.init) + [0, 1, 2]))
        session.select(entry: 502)
        XCTAssertEqual(session.selectedRowItem?.id, "event:e502")
    }

    func testOldGenerationWindowCannotRepopulateANewQuery() async {
        let session = session(count: 1000)
        session.update(query: "daily")
        await session.settle()
        let reads = DelayedWindowReads()
        session.loadEvents = { ids in await reads.load(ids) }
        session.show(days: 500..<506)
        await reads.waitForRequests(1)
        session.update(query: "da")
        session.loadEvents = { ids in DelayedWindowReads.models(ids) }
        session.update(query: "daily")
        reads.complete(0)
        await session.settle()

        XCTAssertEqual(Set(session.events.keys), Set(SearchDayPaging.opening(at: 0, dayCount: 1000).map(Int64.init)))
        XCTAssertEqual(session.selectedEntry, 0)
        XCTAssertEqual(session.total, 1000)
    }

    @MainActor
    private final class DelayedWindowReads {
        private var requests: [(ids: [Int64], continuation: CheckedContinuation<[Int64: AgendaEventModel], Never>)] = []
        var requestCount: Int { requests.count }

        func load(_ ids: [Int64]) async -> [Int64: AgendaEventModel] {
            await withCheckedContinuation { requests.append((ids, $0)) }
        }

        func waitForRequests(_ count: Int) async {
            while requests.count < count { await Task.yield() }
        }

        func complete(_ index: Int) {
            let request = requests[index]
            request.continuation.resume(returning: Self.models(request.ids))
        }

        static func models(_ ids: [Int64]) -> [Int64: AgendaEventModel] {
            Dictionary(uniqueKeysWithValues: ids.map {
                ($0, AgendaEventModel(id: "e\($0)", startTime: "09:00", endTime: "10:00", title: "Daily \($0)"))
            })
        }
    }
}
