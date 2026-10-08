import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

/// The agenda is a continuous run of days: every day in the loaded window
/// has a section ("No events" when empty); events are laid over them.
@MainActor
final class AgendaSectionStoreTests: XCTestCase {
    /// Returns exactly the given days (like EventKit: only days with events).
    private struct SparseProvider: CalendarDataProviding {
        let eventDays: [Date]

        func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel] { [] }

        func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
            eventDays.filter { $0 >= calendar.startOfDay(for: range.start) && $0 <= calendar.startOfDay(for: range.end) }.map {
                AgendaDaySection(date: $0, events: [
                    AgendaEventModel(id: "e-\($0.timeIntervalSince1970)", startTime: "09:00", endTime: "10:00", title: "E")
                ])
            }
        }

        func events(for date: Date, calendar: Calendar) -> [AgendaEventModel] { [] }
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    /// Consecutive calendar days, none missing and none repeated.
    private func assertContinuous(_ sections: [AgendaDaySection], file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in zip(sections, sections.dropFirst()) {
            XCTAssertEqual(calendar.date(byAdding: .day, value: 1, to: a.date), b.date,
                           "gap or duplicate after \(a.date)", file: file, line: line)
        }
    }

    func testEveryDayOfTheWindowHasASectionAndEventsAreKept() async {
        let friday = day(9, 25), monday = day(9, 28)
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: [friday, monday]), calendar: calendar)
        await store.loadInitialWindow(around: day(9, 26))

        assertContinuous(store.sections)
        XCTAssertEqual(store.sections.first?.date, day(9, 19))
        XCTAssertEqual(store.sections.last?.date, day(10, 17))
        let weekend = store.sections.filter { $0.date > friday && $0.date < monday }
        XCTAssertEqual(weekend.count, 2, "Saturday and Sunday are there")
        XCTAssertTrue(weekend.allSatisfy(\.events.isEmpty))
        XCTAssertEqual(store.sections.first { $0.date == friday }?.events.count, 1)
    }

    func testPagingFillsEachChunkWithoutDuplicatesAtTheSeam() async {
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: [day(9, 19)]), calendar: calendar)
        await store.loadInitialWindow(around: day(9, 26))
        await store.loadMoreIfNeeded(nearTopOf: day(9, 19), isAtLoadedContentEdge: true)
        await store.loadMoreIfNeeded(nearBottomOf: day(10, 17), isAtLoadedContentEdge: true)

        assertContinuous(store.sections)
        // A chunk (45 days) beyond each edge of the initial window.
        XCTAssertEqual(store.sections.first?.date, day(8, 5))
        XCTAssertEqual(store.sections.last?.date, day(12, 1))
        XCTAssertEqual(store.sections.first { $0.date == day(9, 19) }?.events.count, 1, "the seam day keeps its events")
    }

    func testScrollingUpDropsFarDaysBelowAndTheyPageBackIn() async {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_791_028_800))
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: []), calendar: calendar)
        await store.loadInitialWindow(around: today)
        // Scroll up page after page, always at the top edge.
        for _ in 0..<6 {
            await store.loadMoreIfNeeded(nearTopOf: store.sections[0].date, isAtLoadedContentEdge: true)
        }
        XCTAssertLessThanOrEqual(store.sections.count, AppConfiguration.agendaMaxLoadedDays + AppConfiguration.agendaKeptDaysBeyondVisible,
                                 "bounded, however far up")
        let last = store.sections.last!.date
        XCTAssertLessThan(last, today, "the days far below (today and after) were dropped")
        let visible = store.sections[0].date
        XCTAssertGreaterThanOrEqual(calendar.dateComponents([.day], from: visible, to: last).day!,
                                    AppConfiguration.agendaKeptDaysBeyondVisible - 1, "the days near the viewport stay")
        // Scrolling back down loads them again, seamlessly.
        await store.loadMoreIfNeeded(nearBottomOf: last, isAtLoadedContentEdge: true)
        XCTAssertGreaterThan(store.sections.last!.date, last)
        XCTAssertEqual(Set(store.sections.map(\.date)).count, store.sections.count, "no duplicate days at the seam")
    }

    func testScrollingDownDropsFarDaysAboveAndTheyPageBackIn() async {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_791_028_800))
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: []), calendar: calendar)
        await store.loadInitialWindow(around: today)
        for _ in 0..<6 {
            await store.loadMoreIfNeeded(nearBottomOf: store.sections.last!.date, isAtLoadedContentEdge: true)
        }
        XCTAssertLessThanOrEqual(store.sections.count, AppConfiguration.agendaMaxLoadedDays + AppConfiguration.agendaChunkDays,
                                 "bounded, however far down")
        let first = store.sections.first!.date
        XCTAssertGreaterThan(first, today, "the days far above (today and before) were dropped")
        let visible = store.sections.last!.date
        XCTAssertGreaterThanOrEqual(calendar.dateComponents([.day], from: first, to: visible).day!,
                                    AppConfiguration.agendaKeptDaysBeyondVisible, "the days near the viewport stay")
        await store.loadMoreIfNeeded(nearTopOf: first, isAtLoadedContentEdge: true)
        XCTAssertLessThan(store.sections.first!.date, first, "scrolling back up loads them again")
        XCTAssertEqual(Set(store.sections.map(\.date)).count, store.sections.count, "no duplicate days at the seam")
    }

    /// Regression: a jump years away was merged with the loaded window, and
    /// the loaded range then spanned every day between them unfetched —
    /// the agenda went from 19 Nov 2026 straight to May 2030, and scrolling
    /// back never filled it.
    func testJumpFarAwayReplacesTheWindowAndScrollingBackStaysContinuous() async {
        let later = calendar.date(from: DateComponents(year: 2030, month: 5, day: 2))!
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: [day(11, 19), later]), calendar: calendar)
        await store.loadInitialWindow(around: day(11, 1))
        await store.ensureLoaded(covering: later)

        assertContinuous(store.sections)
        XCTAssertFalse(store.isLoaded(day(11, 19)), "the old window is gone, not bridged")
        XCTAssertTrue(store.isLoaded(later))
        XCTAssertEqual(store.sections.first { $0.date == later }?.events.count, 1)

        // Scrolling back up pages in contiguously.
        for _ in 0..<3 {
            await store.loadMoreIfNeeded(nearTopOf: store.sections[0].date, isAtLoadedContentEdge: true)
        }
        assertContinuous(store.sections)
    }

    func testFarJumpFillsItsWindowAndDSTDayAppearsOnce() async {
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: []), calendar: calendar)
        await store.loadInitialWindow(around: day(9, 26))
        await store.ensureLoaded(covering: day(12, 1))

        // Next to the loaded window: merged into one continuous run.
        assertContinuous(store.sections)
        XCTAssertEqual(store.sections.first?.date, day(9, 19))
        XCTAssertTrue(store.sections.contains { $0.date == day(12, 1) })

        let dst = AgendaSectionStore(dataProvider: SparseProvider(eventDays: []), calendar: calendar)
        await dst.loadInitialWindow(around: day(10, 24)) // Europe/Warsaw falls back on Oct 25, 2026
        assertContinuous(dst.sections)
        XCTAssertEqual(dst.sections.filter { calendar.isDate($0.date, inSameDayAs: day(10, 25)) }.count, 1)
    }

    func testAdjacentNavigationMergesStayBoundedAndDroppedDaysReload() async {
        let anchor = day(1, 1)
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: []), calendar: calendar)
        await store.loadInitialWindow(around: anchor)
        for jump in 1...24 {
            let target = calendar.date(byAdding: .day, value: jump * 30, to: anchor)!
            await store.ensureLoaded(covering: target)
            XCTAssertLessThanOrEqual(store.sections.count, AppConfiguration.agendaMaxLoadedDays)
            XCTAssertTrue(store.isLoaded(target))
            assertContinuous(store.sections)
        }
        XCTAssertFalse(store.isLoaded(anchor))
        await store.ensureLoaded(covering: anchor)
        XCTAssertTrue(store.isLoaded(anchor), "trimmed coverage is fetched again")
        XCTAssertLessThanOrEqual(store.sections.count, 160)
        assertContinuous(store.sections)
        await store.reload(around: anchor)
        XCTAssertLessThanOrEqual(store.sections.count, 160)
        assertContinuous(store.sections)
    }

    func testNavigationTrimsAroundRequestedDayAcrossDSTInBothDirections() async {
        let anchor = day(10, 25)
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: []), calendar: calendar)
        await store.loadInitialWindow(around: anchor)
        for direction in [1, -1] {
            for step in 1...12 {
                let target = calendar.date(byAdding: .day, value: step * 40 * direction, to: anchor)!
                await store.ensureLoaded(covering: target)
                XCTAssertLessThanOrEqual(store.sections.count, 160)
                XCTAssertTrue(store.sections.contains { $0.date == target })
                assertContinuous(store.sections)
            }
        }
    }
}

extension AgendaSectionStoreTests {
    /// Regression: a store change (e.g. completing a reminder fires
    /// `EKEventStoreChanged`) reloaded the agenda by emptying it and loading
    /// the initial window again — the list collapsed for a moment and the
    /// scroll jumped (27 Sep → 19 Sep). A reload now refreshes what is
    /// loaded, in place.
    func testReloadRefreshesTheLoadedWindowInPlace() async {
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: [day(9, 25)]), calendar: calendar)
        await store.loadInitialWindow(around: day(9, 26))
        await store.loadMoreIfNeeded(nearTopOf: day(9, 19), isAtLoadedContentEdge: true)
        let before = store.sections.map(\.id)
        XCTAssertEqual(before.first, day(8, 5))

        await store.reload(around: day(9, 27))
        XCTAssertEqual(store.sections.map(\.id), before, "same days, same ids — nothing for the scroll position to lose")
        XCTAssertEqual(store.sections.first { $0.date == day(9, 25) }?.events.count, 1)
    }

    func testReloadWithNothingLoadedStillLoadsTheInitialWindow() async {
        let store = AgendaSectionStore(dataProvider: SparseProvider(eventDays: []), calendar: calendar)
        await store.reload(around: day(9, 26))
        XCTAssertEqual(store.sections.first?.date, day(9, 19))
    }
}

extension AgendaSectionStoreTests {
    @MainActor
    private final class DelayedProvider: CalendarDataProviding {
        var suspends = false
        var requests: [(DateInterval, CheckedContinuation<[AgendaDaySection], Never>)] = []
        nonisolated func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel] { [] }
        nonisolated func events(for date: Date, calendar: Calendar) -> [AgendaEventModel] { [] }
        func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
            guard suspends else { return [] }
            return await withCheckedContinuation { requests.append((range, $0)) }
        }
        func finish(_ index: Int) { requests[index].1.resume(returning: []) }
    }

    func testSupersededNavigationCannotResurrectOldRangeOrPlaceholder() async {
        let provider = DelayedProvider()
        let store = AgendaSectionStore(dataProvider: provider, calendar: calendar)
        await store.loadInitialWindow(around: day(1, 1))
        provider.suspends = true
        let earlier = day(6, 1), latest = day(12, 1)
        let old = Task { await store.ensureLoaded(covering: earlier) }
        while provider.requests.count < 1 { await Task.yield() }
        let new = Task { await store.ensureLoaded(covering: latest) }
        while provider.requests.count < 2 { await Task.yield() }
        provider.finish(1)
        await new.value
        let retained = store.sections
        provider.finish(0)
        await old.value
        XCTAssertEqual(store.sections, retained)
        XCTAssertTrue(store.isLoaded(latest))
        XCTAssertFalse(store.sections.contains { $0.date == earlier }, "no stale placeholder outside the retained range")
        assertContinuous(store.sections)
    }

    func testReloadAndPagingFinishingAfterNavigationCannotReinstallDiscardedDays() async {
        let provider = DelayedProvider()
        let store = AgendaSectionStore(dataProvider: provider, calendar: calendar)
        let anchor = day(1, 1), latest = day(12, 1)
        await store.loadInitialWindow(around: anchor)
        provider.suspends = true
        let reload = Task { await store.reload(around: anchor) }
        while provider.requests.count < 1 { await Task.yield() }
        let paging = Task { await store.loadMoreIfNeeded(nearTopOf: store.sections[0].date, isAtLoadedContentEdge: true) }
        while provider.requests.count < 2 { await Task.yield() }
        let navigation = Task { await store.ensureLoaded(covering: latest) }
        while provider.requests.count < 3 { await Task.yield() }
        provider.finish(2)
        await navigation.value
        let retained = store.sections
        provider.finish(0)
        provider.finish(1)
        await reload.value
        await paging.value
        XCTAssertEqual(store.sections, retained)
        XCTAssertFalse(store.isLoaded(anchor))
        XCTAssertTrue(store.isLoaded(latest))
        assertContinuous(store.sections)
    }

    /// Returns what it's told to, so a test can change the calendar.
    private final class MutableProvider: CalendarDataProviding, @unchecked Sendable {
        var sections: [AgendaDaySection] = []
        private(set) var fetches = 0
        func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel] { [] }
        func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
            fetches += 1
            return sections.filter { $0.date >= calendar.startOfDay(for: range.start) && $0.date <= calendar.startOfDay(for: range.end) }
        }
        func events(for date: Date, calendar: Calendar) -> [AgendaEventModel] { [] }
    }

    private func section(_ date: Date, _ ids: [String]) -> AgendaDaySection {
        AgendaDaySection(date: date, events: ids.map { AgendaEventModel(id: $0, startTime: "09:00", endTime: "10:00", title: $0) })
    }

    func testReloadAppliesOnlyRealChangesAndKeepsEveryOtherRow() async {
        let provider = MutableProvider()
        provider.sections = [section(day(9, 25), ["a"]), section(day(9, 28), ["b"])]
        let store = AgendaSectionStore(dataProvider: provider, calendar: calendar)
        await store.loadInitialWindow(around: day(9, 26))
        let before = store.sections

        await store.reload(around: day(9, 26))
        XCTAssertEqual(store.sections, before, "a change elsewhere (a reminder) leaves the agenda as it is")

        provider.sections = [section(day(9, 25), ["a", "new"]), section(day(9, 28), [])]
        await store.reload(around: day(9, 26), animation: .smooth)
        XCTAssertEqual(store.sections.first { $0.date == day(9, 25) }?.events.map(\.id), ["a", "new"])
        XCTAssertEqual(store.sections.first { $0.date == day(9, 28) }?.events, [], "a removed event just leaves its day")
        XCTAssertEqual(store.sections.map(\.id), before.map(\.id), "every day keeps its identity")
    }
}
