import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

/// Scoped to what doesn't require a real `ScrollViewProxy` (there's no
/// way to construct one outside a live `ScrollViewReader`) —
/// `handleScrollRequest`/`moveOneEvent`/`issueScroll` stay exercised via
/// the app itself, same as `PopoverWindowController`/
/// `MenuBarStatusItemController` already are.
@MainActor
final class AgendaScrollCoordinatorTests: XCTestCase {
    /// Unlike `MockCalendarDataProvider` (generated, uncontrollable
    /// data), returns exactly the sections given to it — needed to
    /// construct a deliberately sparse calendar (a multi-week gap
    /// between events) for the content-edge paging tests below.
    private struct StubCalendarDataProvider: CalendarDataProviding {
        let sections: [AgendaDaySection]

        func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel] { [] }

        func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
            sections.filter { $0.date >= range.start && $0.date <= range.end }
        }

        func events(for date: Date, calendar: Calendar) -> [AgendaEventModel] { [] }
    }

    private func store() -> AgendaSectionStore {
        AgendaSectionStore(dataProvider: MockCalendarDataProvider(), calendar: .autoupdatingCurrent)
    }

    func testClearProgrammaticFlagIfNoTarget() {
        let coordinator = AgendaScrollCoordinator(store: store(), scrollTarget: AgendaScrollTarget(date: .now))
        XCTAssertTrue(coordinator.isProgrammaticScroll)

        coordinator.clearProgrammaticFlagIfNoTarget()
        XCTAssertFalse(coordinator.isProgrammaticScroll)
    }

    func testInitWithNoScrollTargetStartsNotProgrammatic() {
        let coordinator = AgendaScrollCoordinator(store: store(), scrollTarget: nil)
        XCTAssertFalse(coordinator.isProgrammaticScroll)
    }

    func testVisibilityChangedReportsNothingWhileProgrammaticScrollIsActive() {
        let coordinator = AgendaScrollCoordinator(store: store(), scrollTarget: AgendaScrollTarget(date: .now))
        coordinator.scrollPhaseChanged(isTracking: true)

        var reported: Date?
        coordinator.visibilityChanged([.day(.now)], isActive: true) { reported = $0 }

        XCTAssertNil(reported, "still programmatic — a user-scroll report would fight the in-flight navigation")
    }

    func testVisibilityChangedReportsNothingWhileInactive() {
        let coordinator = AgendaScrollCoordinator(store: store(), scrollTarget: nil)
        coordinator.scrollPhaseChanged(isTracking: true)

        var reported: Date?
        coordinator.visibilityChanged([.day(.now)], isActive: false) { reported = $0 }

        XCTAssertNil(reported, "this column isn't the one currently on screen")
    }

    func testVisibilityChangedReportsNothingWhileNotUserScrolling() {
        let coordinator = AgendaScrollCoordinator(store: store(), scrollTarget: nil)

        var reported: Date?
        coordinator.visibilityChanged([.day(.now)], isActive: true) { reported = $0 }

        XCTAssertNil(reported, "no scroll phase reported yet — nothing to attribute to the user")
    }

    func testVisibilityChangedAlwaysUpdatesVisibleAnchors() {
        let day = Date.now
        let coordinator = AgendaScrollCoordinator(store: store(), scrollTarget: AgendaScrollTarget(date: day))
        coordinator.visibilityChanged([.day(day)], isActive: false) { _ in }
        XCTAssertEqual(coordinator.visibleAnchors, [.day(day)])
    }

    // MARK: - Content-edge paging (sparse calendar)

    func testContentEdgeTriggersLoadEvenWithoutDateThresholdMatch() async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        // 50 days back: well outside the loaded window's own 30-day
        // reach from a target that far out, so the plain date-threshold
        // check (7 days) could never fire here on its own.
        let sparseDate = calendar.date(byAdding: .day, value: -50, to: today)!
        // Further back still — only reachable if the content-edge-
        // triggered load actually extends the window another chunk.
        let furtherBackDate = calendar.date(byAdding: .day, value: -100, to: today)!
        let provider = StubCalendarDataProvider(sections: [
            AgendaDaySection(date: sparseDate, events: [
                AgendaEventModel(id: "sparse", startTime: "09:00", endTime: "10:00", title: "Sparse")
            ]),
            AgendaDaySection(date: furtherBackDate, events: [
                AgendaEventModel(id: "further-back", startTime: "09:00", endTime: "10:00", title: "Further back")
            ])
        ])
        let store = AgendaSectionStore(dataProvider: provider, calendar: calendar)
        await store.ensureLoaded(covering: sparseDate)
        XCTAssertEqual(store.sections.filter { !$0.events.isEmpty }.map(\.id), [sparseDate], "only the sparse day has events in the initially loaded window")

        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        coordinator.clearProgrammaticFlagIfNoTarget()
        coordinator.scrollPhaseChanged(isTracking: true)
        // Establishes the "moving backward" baseline — direction-gating
        // means the very first call can never itself trigger a load.
        // Every day of the window has a section, so the content edge is the
        // window's first day — well away from the 7-day date threshold of
        // the sparse event day.
        let edge = store.sections[0].date
        coordinator.visibilityChanged([.day(today)], isActive: true) { _ in }
        coordinator.visibilityChanged([.day(edge)], isActive: true) { _ in }

        await coordinator.topPagingTask?.value
        XCTAssertTrue(store.sections.contains(where: { $0.id == furtherBackDate }), "content-edge visibility should have extended the window another chunk back")
    }

    /// Regression: visibility reported while a bottom load ran was dropped,
    /// and when the load (or the re-anchoring after it) left the view at
    /// the new bottom, nothing asked again — scrolling on at the bottom
    /// moves nothing, so the agenda simply stopped (always at the same
    /// chunk boundary) until the reader scrolled back a little.
    func testALoadThatEndsAtTheBottomLoadsTheNextChunkWithoutAnotherScroll() async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let store = AgendaSectionStore(dataProvider: StubCalendarDataProvider(sections: []), calendar: calendar)
        await store.loadInitialWindow(around: today)
        let firstEnd = store.sections.last!.date

        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        coordinator.clearProgrammaticFlagIfNoTarget()
        coordinator.scrollPhaseChanged(isTracking: true)
        let nearEnd = calendar.date(byAdding: .day, value: -3, to: firstEnd)!
        coordinator.visibilityChanged([.day(today)], isActive: true) { _ in }
        coordinator.visibilityChanged([.day(nearEnd)], isActive: true) { _ in }
        let firstLoad = try? XCTUnwrap(coordinator.bottomPagingTask)

        // While it loads, the reader reaches what will be its last day:
        // reported, but dropped — the load owns the edge.
        let newEnd = calendar.date(byAdding: .day, value: AppConfiguration.agendaChunkDays, to: firstEnd)!
        coordinator.visibilityChanged([.day(newEnd)], isActive: true) { _ in }

        await firstLoad?.value
        XCTAssertEqual(store.sections.map(\.date).filter { $0 >= newEnd }.first, newEnd)
        // No further scroll event: the finished load re-checks and pages on.
        await coordinator.bottomPagingTask?.value
        XCTAssertGreaterThan(store.sections.last!.date, newEnd, "sitting at the bottom after a load pages on by itself")
    }

    /// The bug: dragging the scroll bar's knob reports no SwiftUI scroll
    /// phase, so the agenda stopped at the end of what was loaded.
    func testDraggingTheScrollerPagesAndMovesTheGrid() async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let store = AgendaSectionStore(dataProvider: StubCalendarDataProvider(sections: []), calendar: calendar)
        await store.loadInitialWindow(around: today)
        let firstEnd = store.sections.last!.date

        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        coordinator.clearProgrammaticFlagIfNoTarget()
        coordinator.scrollerTrackingChanged(true, proxy: nil) { _ in }
        var reported: Date?
        let nearEnd = calendar.date(byAdding: .day, value: -3, to: firstEnd)!
        coordinator.visibilityChanged([.day(today)], isActive: true) { reported = $0 }
        coordinator.visibilityChanged([.day(nearEnd)], isActive: true) { reported = $0 }

        XCTAssertEqual(reported, nearEnd, "the month grid follows the drag")
        let load = try? XCTUnwrap(coordinator.bottomPagingTask, "pages while the knob is dragged")
        await load?.value
        XCTAssertGreaterThan(store.sections.last!.date, firstEnd)
    }

    func testAScrollerClickReportedAfterItEndedStillMovesTheGrid() async throws {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let store = AgendaSectionStore(dataProvider: StubCalendarDataProvider(sections: []), calendar: calendar)
        await store.loadInitialWindow(around: today)
        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        coordinator.clearProgrammaticFlagIfNoTarget()

        // A track click: tracking ends before SwiftUI reports the new spot.
        let later = calendar.date(byAdding: .day, value: 10, to: today)!
        var reported: Date?
        coordinator.scrollerTrackingChanged(true, proxy: nil) { reported = $0 }
        coordinator.scrollerTrackingChanged(false, proxy: nil) { reported = $0 }
        coordinator.visibilityChanged([.day(later)], isActive: true) { reported = $0 }
        XCTAssertNil(reported, "after tracking, a report alone isn't a user scroll")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reported, later, "the check once tracking ended picks it up")
    }

    /// Every day has a section, so a load from the top edge always prepends
    /// a full chunk and moves the edge — a fruitless load that retries from
    /// the same spot (what the content-edge latch guards against) can't
    /// happen even in a calendar with no events at all.
    func testLoadingFromTheTopEdgeAlwaysMovesTheEdgeByAChunk() async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let store = AgendaSectionStore(dataProvider: StubCalendarDataProvider(sections: []), calendar: calendar)
        await store.loadInitialWindow(around: today)
        let edge = store.sections[0].date

        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        coordinator.clearProgrammaticFlagIfNoTarget()
        coordinator.scrollPhaseChanged(isTracking: true)
        coordinator.visibilityChanged([.day(today)], isActive: true) { _ in }
        coordinator.visibilityChanged([.day(edge)], isActive: true) { _ in }
        await coordinator.topPagingTask?.value

        XCTAssertEqual(store.sections[0].date, calendar.date(byAdding: .day, value: -AppConfiguration.agendaChunkDays, to: edge))
        XCTAssertTrue(store.sections.allSatisfy(\.events.isEmpty), "empty days, still one section each")
    }

    func testTopPagingIgnoresAForwardScrollEvenAtTheInitialThreshold() async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        // Reproduces the exact coincidence: `loadInitialWindow`'s behind
        // window and the edge-load threshold are both 7 days, so today
        // sits exactly at the threshold — satisfied at rest, not just
        // "near" it.
        let thresholdDate = calendar.date(byAdding: .day, value: -AppConfiguration.agendaEdgeLoadThresholdDays, to: today)!
        let store = AgendaSectionStore(dataProvider: MockCalendarDataProvider(), calendar: calendar)
        await store.loadInitialWindow(around: today)
        let sectionsBefore = store.sections.map(\.id)

        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        coordinator.clearProgrammaticFlagIfNoTarget()
        coordinator.scrollPhaseChanged(isTracking: true)

        // Baseline at the threshold date, then a *forward* scroll (a
        // later visible day) — must not be read as "moving backward"
        // just because the baseline itself already sat at the threshold.
        coordinator.visibilityChanged([.day(thresholdDate)], isActive: true) { _ in }
        let laterDate = calendar.date(byAdding: .day, value: 1, to: thresholdDate)!
        coordinator.visibilityChanged([.day(laterDate)], isActive: true) { _ in }

        XCTAssertNil(coordinator.topPagingTask, "a forward scroll should never trigger backward paging")
        XCTAssertEqual(store.sections.map(\.id), sectionsBefore, "nothing should have been loaded")
    }

    /// Regression: scrolling back through days that are already loaded
    /// (far from the loaded top) must not start a top "load" — its
    /// follow-up position correction snapped every newly visible day's
    /// header to the top, so scrolling up felt like jumping day by day.
    func testScrollingBackWellInsideTheLoadedWindowDoesNotPage() async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let store = AgendaSectionStore(dataProvider: MockCalendarDataProvider(), calendar: calendar)
        await store.loadInitialWindow(around: today)
        // One chunk further back is already loaded, as after the first page.
        await store.loadMoreIfNeeded(nearTopOf: store.sections[0].date, isAtLoadedContentEdge: true)

        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        coordinator.clearProgrammaticFlagIfNoTarget()
        coordinator.scrollPhaseChanged(isTracking: true)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        coordinator.visibilityChanged([.day(yesterday)], isActive: true) { _ in }
        coordinator.visibilityChanged([.day(twoDaysAgo)], isActive: true) { _ in }

        XCTAssertNil(coordinator.topPagingTask, "nothing to load this far from the loaded top")
        XCTAssertEqual(coordinator.topScrollCorrections, 0)
    }

    func testTopCorrectionOnlyWhenSectionsWereActuallyPrepended() async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let sparseDate = calendar.date(byAdding: .day, value: -50, to: today)!
        // Loading further back finds nothing: no prepend, so no correction.
        let provider = StubCalendarDataProvider(sections: [
            AgendaDaySection(date: sparseDate, events: [
                AgendaEventModel(id: "sparse", startTime: "09:00", endTime: "10:00", title: "Sparse")
            ])
        ])
        let store = AgendaSectionStore(dataProvider: provider, calendar: calendar)
        await store.ensureLoaded(covering: sparseDate)
        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        coordinator.clearProgrammaticFlagIfNoTarget()
        coordinator.scrollPhaseChanged(isTracking: true)
        coordinator.visibilityChanged([.day(today)], isActive: true) { _ in }
        coordinator.visibilityChanged([.day(sparseDate)], isActive: true) { _ in }
        await coordinator.topPagingTask?.value
        XCTAssertEqual(coordinator.topScrollCorrections, 0, "nothing was prepended, so the position must be left alone")
    }
}
