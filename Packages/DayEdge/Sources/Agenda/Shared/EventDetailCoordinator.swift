import AppKit
import Foundation
import Observation
import Domain
import UI

/// Owns the agenda's keyboard-driven event selection and the event-detail
/// popover's presentation/focus/action state — split out of
/// `RootView`, which used to hold all of this directly as
/// `@State` alongside every other cross-cutting concern in the app. Takes
/// `isMonthActive` as a parameter on the methods that need it rather than
/// reading view-mode state itself, so this type never needs to know
/// `ViewMode` (or the fact that there even are multiple view
/// modes) exists.
@MainActor
@Observable
package final class EventDetailCoordinator {
    package init() {}

    package private(set) var keyboardSelectedEvent: AgendaKeyboardSelection?
    package private(set) var detailPresentationRequest: EventDetailPresentationRequest?
    package private(set) var presentedEventDetailID: String?
    package private(set) var focusedEventDetailControl: EventDetailFocusedControl?
    package private(set) var detailActionRequest: EventDetailActionRequest?

    package func selectKeyboardEvent(_ selection: AgendaKeyboardSelection?) {
        keyboardSelectedEvent = selection
    }

    /// Called by `AgendaNavigationCoordinator` (via a closure captured at
    /// construction, not a direct reference to that type) whenever the
    /// selected date changes — a keyboard-selected event from the
    /// previous day shouldn't stay "selected" once you've navigated away.
    package func clearKeyboardSelection() {
        keyboardSelectedEvent = nil
    }

    package func presentationChanged(eventID: String, isShowing: Bool) {
        if isShowing {
            presentedEventDetailID = eventID
        } else if presentedEventDetailID == eventID {
            presentedEventDetailID = nil
            focusedEventDetailControl = nil
        }
    }

    package func actionFocusChanged(eventID: String, action: EventDetailFocusableAction?) {
        if let action {
            focusedEventDetailControl = EventDetailFocusedControl(eventID: eventID, action: action)
        } else if focusedEventDetailControl?.eventID == eventID {
            focusedEventDetailControl = nil
        }
    }

    /// The Return-key/shortcut path: if a detail popover is already open
    /// with a control focused inside it, activate that control instead of
    /// re-toggling the popover itself.
    package func openSelectedDetails(isMonthActive: Bool) {
        if let focusedEventDetailControl,
           focusedEventDetailControl.eventID == presentedEventDetailID {
            activateFocusedControl()
            return
        }
        guard isMonthActive, let keyboardSelectedEvent else { return }
        detailPresentationRequest = EventDetailPresentationRequest(
            eventID: keyboardSelectedEvent.event.id,
            action: .toggle
        )
    }

    package func activateFocusedControl() {
        guard let focusedEventDetailControl else { return }
        switch focusedEventDetailControl.action {
        case .copyLink:
            detailActionRequest = EventDetailActionRequest(eventID: focusedEventDetailControl.eventID, action: .copyLink)
        case .join:
            detailActionRequest = EventDetailActionRequest(eventID: focusedEventDetailControl.eventID, action: .join)
        case .notes:
            detailActionRequest = EventDetailActionRequest(eventID: focusedEventDetailControl.eventID, action: .toggleNotes)
        }
    }

    /// The Escape-key path. Returns whether there was actually a
    /// presented detail popover to dismiss, so `RootView` can
    /// fall through to its other Escape cases (clear search focus, clear
    /// search text) without reading this coordinator's private state
    /// directly.
    @discardableResult
    package func dismissPresentedDetails() -> Bool {
        guard let presentedEventDetailID else { return false }
        detailPresentationRequest = EventDetailPresentationRequest(eventID: presentedEventDetailID, action: .dismiss)
        return true
    }
}
