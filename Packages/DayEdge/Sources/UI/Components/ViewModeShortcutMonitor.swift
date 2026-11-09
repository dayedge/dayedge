import AppKit
import SwiftUI
import Domain

/// Routes the view switches (`KeyboardShortcutSettings` — ⌘1–⌘4 for the
/// view modes, ⌥⌘1–⌥⌘4 for Tasks' Overview views) to `onSelect`. Uses the same local-monitor
/// approach as `ArrowKeyMonitor`, for the same reason: the search field
/// always holds keyboard focus (see `SearchBarView`), so a plain SwiftUI
/// `.keyboardShortcut` on the switcher's own buttons can't be relied on to
/// see the key event first.
package struct ViewModeShortcutMonitor: NSViewRepresentable {
    package let onSelect: (PanelCommand) -> Void

    package func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.installMonitor()
        return view
    }

    package func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSelect = onSelect
    }

    package func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    package static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    package final class Coordinator {
        package weak var hostView: NSView?
        package var onSelect: (PanelCommand) -> Void
        private var monitor: Any?

        package init(onSelect: @escaping (PanelCommand) -> Void) {
            self.onSelect = onSelect
        }

        package func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      event.window === self.hostView?.window else {
                    return event
                }

                // The user's binding, exactly as recorded (modifiers included).
                switch KeyboardShortcutSettings.resolve(event) {
                case let command? where command.isViewSwitch:
                    self.onSelect(command)
                    return nil
                default:
                    return event
                }
            }
        }

        package func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }

    package init(onSelect: @escaping (PanelCommand) -> Void) {
        self.onSelect = onSelect
    }
}
