import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

/// An unseen jump is "prepared" only once its day is on screen: what waits
/// for it (the window, Month) must not show the list still settling.
@MainActor
final class AgendaLandingTests: XCTestCase {
    private let day = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 26))!

    private func coordinator() -> AgendaScrollCoordinator {
        AgendaScrollCoordinator(store: AgendaSectionStore(dataProvider: MockCalendarDataProvider(), calendar: .autoupdatingCurrent),
                                scrollTarget: nil)
    }

    func testASettledListLeavesWithItsTopRow() {
        let scroll = coordinator()
        scroll.visibilityChanged([.day(day)], isActive: true) { _ in }
        XCTAssertEqual(scroll.leavingAnchor, .day(day))
    }

    func testAListLeavingMidJumpLeavesNoRowToComeBackTo() {
        let scroll = AgendaScrollCoordinator(
            store: AgendaSectionStore(dataProvider: MockCalendarDataProvider(), calendar: .autoupdatingCurrent),
            scrollTarget: AgendaScrollTarget(date: day)
        )
        scroll.visibilityChanged([.day(day.addingTimeInterval(-86_400 * 7))], isActive: true) { _ in }
        XCTAssertNil(scroll.leavingAnchor)
    }

    func testAnUnseenJumpIsNotPreparedBeforeItsDayShows() async {
        let scroll = coordinator()
        var prepared = 0
        scroll.reportPrepared(AgendaScrollTarget(date: day, animated: false), at: .day(day), animated: false) { _ in prepared += 1 }
        await Task.yield()
        XCTAssertEqual(prepared, 0)
    }

    func testAnUnseenJumpIsPreparedOnceItsDayShows() async {
        let scroll = coordinator()
        var prepared = 0
        scroll.reportPrepared(AgendaScrollTarget(date: day, animated: false), at: .day(day), animated: false) { _ in prepared += 1 }
        scroll.visibilityChanged([.day(day)], isActive: false) { _ in }
        scroll.visibilityChanged([.day(day)], isActive: false) { _ in }
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(prepared, 1)
    }

    func testAnotherDayShowingIsNotTheLanding() async {
        let scroll = coordinator()
        var prepared = 0
        let otherDay = day.addingTimeInterval(-86_400 * 30)
        scroll.reportPrepared(AgendaScrollTarget(date: day, animated: false), at: .day(day), animated: false) { _ in prepared += 1 }
        scroll.visibilityChanged([.day(otherDay)], isActive: false) { _ in }
        await Task.yield()
        XCTAssertEqual(prepared, 0)
    }

    func testAJumpThatNeverShowsIsPreparedByTheFallback() async {
        let scroll = coordinator()
        scroll.landingFallbackDelay = .zero
        let expectation = expectation(description: "prepared")
        scroll.reportPrepared(AgendaScrollTarget(date: day, animated: false), at: .day(day), animated: false) { _ in
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testAWatchedJumpIsPreparedAtOnce() {
        let scroll = coordinator()
        var prepared = 0
        scroll.reportPrepared(AgendaScrollTarget(date: day), at: .day(day), animated: true) { _ in prepared += 1 }
        XCTAssertEqual(prepared, 1)
    }

    // MARK: Coming back to where Month was left

    private func navigation() -> AgendaNavigationCoordinator {
        let provider = MockCalendarDataProvider()
        return AgendaNavigationCoordinator(
            viewModel: CalendarViewModel(dataProvider: provider, visibleMonth: day, selectedDate: day),
            agendaStore: AgendaSectionStore(dataProvider: provider, calendar: .autoupdatingCurrent),
            presentationCoordinator: PopoverPresentationCoordinator(),
            onWillChangeDate: {}
        )
    }

    func testLeavingMonthRemembersItsTopRowUnseenAndUnselected() {
        let navigation = navigation()
        navigation.rememberMonthPosition(.event(sectionID: day, eventID: "standup"))
        let target = navigation.requestedMonthAgendaDate
        XCTAssertEqual(target?.eventID, "standup")
        XCTAssertEqual(target?.restoresPosition, true)
        XCTAssertEqual(target?.animated, false)
    }

    func testADateAskedForAfterwardsReplacesTheRememberedRow() {
        let navigation = navigation()
        navigation.rememberMonthPosition(.day(day))
        navigation.moveSelectedDay(by: 3)
        XCTAssertEqual(navigation.requestedMonthAgendaDate?.restoresPosition, false)
    }

    func testNothingOnScreenRemembersNothing() {
        let navigation = navigation()
        let before = navigation.requestedMonthAgendaDate
        navigation.rememberMonthPosition(nil)
        XCTAssertEqual(navigation.requestedMonthAgendaDate, before)
    }
}
