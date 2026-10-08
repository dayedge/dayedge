import AppKit
import SwiftUI
import Domain

/// Routes the view-mode switch shortcuts (`KeyboardShortcutSettings`
/// — ⌘1–⌘4 by default) to `onSelectMode`. Uses the same local-monitor
/// approach as `ArrowKeyMonitor`, for the same reason: the search field
/// always holds keyboard focus (see `SearchBarView`), so a plain SwiftUI
/// `.keyboardShortcut` on the switcher's own buttons can't be relied on to
/// see the key event first.
package struct ViewModeShortcutMonitor: NSViewRepresentable {
    package let onSelectMode: (ViewMode) -> Void

    package func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.installMonitor()
        return view
    }

    package func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSelectMode = onSelectMode
    }

    package func makeCoordinator() -> Coordinator {
        Coordinator(onSelectMode: onSelectMode)
    }

    package static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    package final class Coordinator {
        package weak var hostView: NSView?
        package var onSelectMode: (ViewMode) -> Void
        private var monitor: Any?

        package init(onSelectMode: @escaping (ViewMode) -> Void) {
            self.onSelectMode = onSelectMode
        }

        package func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      event.window === self.hostView?.window else {
                    return event
                }

                // The user's binding, exactly as recorded (modifiers included).
                guard case .viewMode(let mode)? = KeyboardShortcutSettings.resolve(event) else {
                    return event
                }

                self.onSelectMode(mode)
                return nil
            }
        }

        package func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }

    package init(onSelectMode: @escaping (ViewMode) -> Void) {
        self.onSelectMode = onSelectMode
    }
}
