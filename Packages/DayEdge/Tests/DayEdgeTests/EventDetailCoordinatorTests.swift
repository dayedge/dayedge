import XCTest
@testable import Shell
@testable import Domain
@testable import UI
@testable import Agenda

@MainActor
final class EventDetailCoordinatorTests: XCTestCase {
    private func event(id: String = "event-1", videoService: VideoConferenceService? = nil, videoURL: String? = nil) -> AgendaEventModel {
        AgendaEventModel(id: id, title: id, videoService: videoService, videoURL: videoURL)
    }

    private func selection(id: String = "event-1") -> AgendaKeyboardSelection {
        AgendaKeyboardSelection(date: .now, event: event(id: id))
    }

    func testSelectAndClearKeyboardSelection() {
        let coordinator = EventDetailCoordinator()
        coordinator.selectKeyboardEvent(selection())
        XCTAssertNotNil(coordinator.keyboardSelectedEvent)

        coordinator.clearKeyboardSelection()
        XCTAssertNil(coordinator.keyboardSelectedEvent)
    }

    func testPresentationChangeTracksShownEventAndClearsFocusOnClose() {
        let coordinator = EventDetailCoordinator()
        coordinator.presentationChanged(eventID: "event-1", isShowing: true)
        XCTAssertEqual(coordinator.presentedEventDetailID, "event-1")

        coordinator.actionFocusChanged(eventID: "event-1", action: .copyLink)
        XCTAssertEqual(coordinator.focusedEventDetailControl?.eventID, "event-1")

        coordinator.presentationChanged(eventID: "event-1", isShowing: false)
        XCTAssertNil(coordinator.presentedEventDetailID)
        XCTAssertNil(coordinator.focusedEventDetailControl, "closing the popover should also clear its focused control")
    }

    func testPresentationChangeIgnoresCloseForADifferentEvent() {
        let coordinator = EventDetailCoordinator()
        coordinator.presentationChanged(eventID: "event-1", isShowing: true)

        // A stale close report for a different (e.g. previously open) event
        // must not clobber the one that's actually showing now.
        coordinator.presentationChanged(eventID: "event-2", isShowing: false)
        XCTAssertEqual(coordinator.presentedEventDetailID, "event-1")
    }

    func testActionFocusChangeClearsOnlyWhenSameEventLosesFocus() {
        let coordinator = EventDetailCoordinator()
        coordinator.actionFocusChanged(eventID: "event-1", action: .join)
        XCTAssertNotNil(coordinator.focusedEventDetailControl)

        coordinator.actionFocusChanged(eventID: "event-2", action: nil)
        XCTAssertNotNil(coordinator.focusedEventDetailControl, "a different event losing focus shouldn't clear this one's")

        coordinator.actionFocusChanged(eventID: "event-1", action: nil)
        XCTAssertNil(coordinator.focusedEventDetailControl)
    }

    func testOpenSelectedDetailsNoOpsWhenMonthNotActive() {
        let coordinator = EventDetailCoordinator()
        coordinator.selectKeyboardEvent(selection())
        coordinator.openSelectedDetails(isMonthActive: false)
        XCTAssertNil(coordinator.detailPresentationRequest)
    }

    func testOpenSelectedDetailsTogglesWhenMonthActive() {
        let coordinator = EventDetailCoordinator()
        coordinator.selectKeyboardEvent(selection(id: "event-42"))
        coordinator.openSelectedDetails(isMonthActive: true)
        XCTAssertEqual(coordinator.detailPresentationRequest?.eventID, "event-42")
        XCTAssertEqual(coordinator.detailPresentationRequest?.action, .toggle)
    }

    func testOpenSelectedDetailsActivatesFocusedControlInsteadOfRetoggling() {
        let coordinator = EventDetailCoordinator()
        coordinator.selectKeyboardEvent(selection(id: "event-1"))
        coordinator.presentationChanged(eventID: "event-1", isShowing: true)
        coordinator.actionFocusChanged(eventID: "event-1", action: .notes)

        coordinator.openSelectedDetails(isMonthActive: true)

        XCTAssertNil(coordinator.detailPresentationRequest, "should not have issued a new toggle request")
        XCTAssertEqual(coordinator.detailActionRequest?.eventID, "event-1")
        XCTAssertEqual(coordinator.detailActionRequest?.action, .toggleNotes)
    }

    func testActivateFocusedControlMapsEachActionCorrectly() {
        let coordinator = EventDetailCoordinator()
        coordinator.actionFocusChanged(eventID: "event-1", action: .copyLink)
        coordinator.activateFocusedControl()
        XCTAssertEqual(coordinator.detailActionRequest?.action, .copyLink)

        coordinator.actionFocusChanged(eventID: "event-1", action: .join)
        coordinator.activateFocusedControl()
        XCTAssertEqual(coordinator.detailActionRequest?.action, .join)

        coordinator.actionFocusChanged(eventID: "event-1", action: .notes)
        coordinator.activateFocusedControl()
        XCTAssertEqual(coordinator.detailActionRequest?.action, .toggleNotes)
    }

    func testDismissPresentedDetailsReturnsFalseWhenNothingPresented() {
        let coordinator = EventDetailCoordinator()
        XCTAssertFalse(coordinator.dismissPresentedDetails())
        XCTAssertNil(coordinator.detailPresentationRequest)
    }

    func testDismissPresentedDetailsReturnsTrueAndRequestsDismissal() {
        let coordinator = EventDetailCoordinator()
        coordinator.presentationChanged(eventID: "event-1", isShowing: true)

        XCTAssertTrue(coordinator.dismissPresentedDetails())
        XCTAssertEqual(coordinator.detailPresentationRequest?.eventID, "event-1")
        XCTAssertEqual(coordinator.detailPresentationRequest?.action, .dismiss)
    }
}
