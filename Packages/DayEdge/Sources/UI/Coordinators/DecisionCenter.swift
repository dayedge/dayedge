import AppKit
import Observation
import Domain

/// The panel's one active decision (docked at its bottom). A new request
/// replaces an unanswered one, which counts as cancelled — cards never
/// stack. Keys go here first while a card is up (see `ActionShortcutMonitor`):
/// Esc cancels, ← / → move between the actions, ↩ runs the selected one.
@MainActor
@Observable
package final class DecisionCenter {
    package static let shared = DecisionCenter()

    package private(set) var current: DecisionRequest?
    /// The action ↩ would run.
    package private(set) var selectedID: DecisionAction.ID?
    /// ← / → have been used: the selection wears a focus ring. Until then the
    /// default button's prominence says it all.
    package private(set) var isNavigatingByKeyboard = false

    package func present(_ request: DecisionRequest) {
        if current != nil { cancel() }
        current = request
        selectedID = request.defaultAction?.id
        isNavigatingByKeyboard = false
    }

    /// An action of the current card, or one from a split button's menu.
    package func choose(_ action: DecisionAction) {
        guard let actions = current?.actions,
              actions.contains(where: { $0.id == action.id || $0.alternatives.contains { $0.id == action.id } }) else { return }
        current = nil
        selectedID = nil
        action.handler()
    }

    package func cancel() {
        guard let action = current?.cancelAction else {
            current = nil
            return
        }
        choose(action)
    }

    package func select(_ id: DecisionAction.ID) { selectedID = id }

    /// Moves the selection left (-1) or right (+1), stopping at the ends.
    package func moveSelection(_ step: Int) {
        guard let actions = current?.actions, !actions.isEmpty else { return }
        let index = actions.firstIndex { $0.id == selectedID } ?? 0
        selectedID = actions[min(max(index + step, 0), actions.count - 1)].id
        isNavigatingByKeyboard = true
    }

    /// Esc, ←, →, ↩ while a card is up; true when used.
    package func handleKey(_ event: NSEvent) -> Bool {
        guard let current, !ShortcutRecording.isRecording else { return false }
        switch event.keyCode {
        case 53: cancel()                    // Esc
        case 123: moveSelection(-1)          // ←
        case 124: moveSelection(1)           // →
        case 36, 76:                         // ↩, Enter
            if let action = current.actions.first(where: { $0.id == selectedID }) { choose(action) }
        default: return false
        }
        return true
    }
}
