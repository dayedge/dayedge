import Foundation
import XCTest
@testable import Domain
@testable import Agenda

@MainActor
final class AgendaBottomPagingTests: XCTestCase {
    func testForwardScrollInsideLoadedWindowDoesNotStartBottomPaging() async {
        let (store, anchor, calendar) = await loadedStore()
        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        defer { stop(coordinator) }
        coordinator.scrollPhaseChanged(isTracking: true)
        coordinator.visibilityChanged([.day(anchor)], isActive: true) { _ in }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: anchor)!
        coordinator.visibilityChanged([.day(nextDay)], isActive: true) { _ in }

        XCTAssertNil(coordinator.bottomPagingTask)
    }

    func testRecheckInsideLoadedWindowDoesNotStartBottomPaging() async {
        let (store, anchor, calendar) = await loadedStore()
        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        defer { stop(coordinator) }
        let middle = calendar.date(byAdding: .day, value: 10, to: anchor)!
        coordinator.visibilityChanged([.day(middle)], isActive: true) { _ in }

        coordinator.recheckPagingAfterLoad(proxy: nil)

        XCTAssertNil(coordinator.bottomPagingTask)
    }

    func testCompletedBottomLoadStopsWhenVisibleDayIsCovered() async throws {
        let (store, anchor, calendar) = await loadedStore()
        let originalEnd = try XCTUnwrap(store.sections.last?.date)
        let coordinator = AgendaScrollCoordinator(store: store, scrollTarget: nil)
        defer { stop(coordinator) }
        coordinator.scrollPhaseChanged(isTracking: true)
        coordinator.visibilityChanged([.day(anchor)], isActive: true) { _ in }
        let nearEnd = calendar.date(byAdding: .day, value: -3, to: originalEnd)!
        coordinator.visibilityChanged([.day(nearEnd)], isActive: true) { _ in }
        let load = try XCTUnwrap(coordinator.bottomPagingTask)

        await load.value

        XCTAssertGreaterThan(try XCTUnwrap(store.sections.last?.date), originalEnd)
        XCTAssertNil(coordinator.bottomPagingTask)
    }

    private func loadedStore() async -> (AgendaSectionStore, Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9))!
        let store = AgendaSectionStore(dataProvider: EmptyCalendarDataProvider(), calendar: calendar)
        await store.loadInitialWindow(around: anchor)
        return (store, anchor, calendar)
    }

    private func stop(_ coordinator: AgendaScrollCoordinator) {
        coordinator.isListActive = false
        coordinator.cancelNavigation()
    }

    private struct EmptyCalendarDataProvider: CalendarDataProviding {
        func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel] { [] }
        func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] { [] }
        func events(for date: Date, calendar: Calendar) -> [AgendaEventModel] { [] }
    }
}
