import Foundation
import Observation
import Domain
import Agenda

enum PopoverOpenBehavior: Equatable {
    case todayNow
    case preserve
}

/// Something the status menu asks the popover to do once it's open.
enum PopoverCommand: Equatable {
    /// The search palette, focused.
    case search
    /// The app, its composer focused (the current conversation).
    case ask
    /// The event, in the Day view.
    case showEvent(OccurrenceNavigationTarget)
    /// The Tasks view (overdue and today lead it).
    case showTodayTasks
}

struct PopoverCommandRequest: Equatable {
    let id = UUID()
    let command: PopoverCommand
}

struct PopoverOpenRequest: Equatable {
    let id = UUID()
    let openedAt: Date
    let behavior: PopoverOpenBehavior
}

/// Bridges AppKit's borderless-window lifecycle into SwiftUI without global
/// notifications. The root view only acts on `.todayNow`; `.preserve` is an
/// intentional no-op that leaves both permanently-mounted scroll views alone.
///
/// Also the seam `AppDelegate` uses to keep the window itself hidden until
/// that `.todayNow` positioning has actually finished — see `onReady` and
/// `markReady(_:)`. Without this, `AppDelegate` would reveal the window
/// immediately on click and the root view's scroll-to-today would happen
/// visibly a frame or two later, however briefly.
@MainActor
@Observable
final class PopoverPresentationCoordinator {
    private(set) var openRequest: PopoverOpenRequest?
    /// The latest status-menu command; sent only once the window is shown,
    /// so an open's today-positioning never overrides it.
    private(set) var command: PopoverCommandRequest?
    private(set) var isVisible = false
    var pointerXOffset: CGFloat = 0
    private var lastHiddenAt: Date?

    /// Set by `AppDelegate` right after starting an open — called once the
    /// root view reports (`markReady`) that positioning for the current
    /// `openRequest` is done and it's safe to actually show the window.
    var onReady: ((UUID) -> Void)?

    @discardableResult
    func willOpen(at date: Date = .now) -> PopoverOpenRequest {
        isVisible = true
        // `PopoverReopenSettings.timeoutMinutes == 0` means "never
        // restore" — every open is `.todayNow` regardless of how quickly
        // it follows the last close, so this short-circuits rather than
        // relying on a same-instant `<= 0` comparison below.
        let timeoutMinutes = PopoverReopenSettings.timeoutMinutes
        let shouldPreserve = timeoutMinutes > 0 && (lastHiddenAt.map {
            date.timeIntervalSince($0) <= PopoverReopenSettings.timeoutInterval
        } ?? false)
        let request = PopoverOpenRequest(
            openedAt: date,
            behavior: shouldPreserve ? .preserve : .todayNow
        )
        openRequest = request
        return request
    }

    /// Called by the root view once positioning for `requestID` has
    /// actually taken effect. A no-op if `requestID` isn't (or is no
    /// longer) the current open request — e.g. a stale signal arriving
    /// after the popover's already been closed and reopened.
    func markReady(_ requestID: UUID) {
        guard requestID == openRequest?.id else { return }
        onReady?(requestID)
    }

    func send(_ command: PopoverCommand) {
        self.command = PopoverCommandRequest(command: command)
    }

    func didHide(at date: Date = .now) {
        isVisible = false
        lastHiddenAt = date
        onReady = nil
    }
}

extension PopoverPresentationCoordinator: PanelRevealing {
    var openRequestID: UUID? { openRequest?.id }
}
