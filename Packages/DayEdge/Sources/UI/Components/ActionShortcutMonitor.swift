import AppKit
import SwiftUI

/// Routes configurable calendar actions before the always-focused search
/// field can consume them. When search contains text, navigation and event
/// actions pass through untouched so normal text editing keeps priority.
package struct ActionShortcutMonitor: NSViewRepresentable {
    package let isNavigationEnabled: Bool
    /// Runs the action; false = it doesn't apply here (wrong view, nothing
    /// selected), and the key goes on to whoever else wants it.
    package let onAction: (KeyboardCommandAction) -> Bool

    package func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.installMonitor()
        return view
    }

    package func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isNavigationEnabled = isNavigationEnabled
        context.coordinator.onAction = onAction
    }

    package func makeCoordinator() -> Coordinator {
        Coordinator(isNavigationEnabled: isNavigationEnabled, onAction: onAction)
    }

    package static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    /// Popovers are child windows whose fields (a task's title, notes…)
    /// own the keyboard while typing: no the app shortcut fires there, so
    /// Space and Return edit text and Esc cancels the edit (the field's
    /// own handling) instead of closing the popover. With no field active,
    /// Esc closes as usual. The main window keeps its routing.
    package static func shouldHandle(_ action: KeyboardCommandAction, inChildWindow: Bool, isTextEditing: Bool) -> Bool {
        !(inChildWindow && isTextEditing)
    }

    package final class Coordinator {
        package weak var hostView: NSView?
        package var isNavigationEnabled: Bool
        package var onAction: (KeyboardCommandAction) -> Bool
        private var monitor: Any?

        package init(isNavigationEnabled: Bool, onAction: @escaping (KeyboardCommandAction) -> Bool) {
            self.isNavigationEnabled = isNavigationEnabled
            self.onAction = onAction
        }

        package func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // A decision on screen takes Esc, ← / →, ↩ first (local
                // monitors run on the main thread).
                if MainActor.assumeIsolated({ DecisionCenter.shared.handleKey(event) }) { return nil }
                // Then an open details card (↑ / ↓ / ↩ / Esc are its own).
                if MainActor.assumeIsolated({ DetailKeyboard.shared.handle(event) }) { return nil }
                guard let self,
                      let hostWindow = self.hostView?.window,
                      let eventWindow = event.window,
                      eventWindow.isSelfOrChild(of: hostWindow),
                      case .action(let action)? = KeyboardShortcutSettings.resolve(event) else {
                    return event
                }

                guard ActionShortcutMonitor.shouldHandle(
                    action,
                    inChildWindow: eventWindow !== hostWindow,
                    isTextEditing: eventWindow.firstResponder is NSTextView
                ) else { return event }

                let worksWhileEditing = action == .focusSearch || action == .escapeSearch || action == .today
                guard self.isNavigationEnabled || worksWhileEditing else { return event }

                return Self.outcome(of: event, handled: self.onAction(action))
            }
        }

        /// A handled key stops here; one that didn't apply goes on.
        nonisolated static func outcome(of event: NSEvent, handled: Bool) -> NSEvent? { handled ? nil : event }

        package func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    package init(isNavigationEnabled: Bool, onAction: @escaping (KeyboardCommandAction) -> Bool) {
        self.isNavigationEnabled = isNavigationEnabled
        self.onAction = onAction
    }
}
