import AppKit
import SwiftUI

/// Routes unmodified arrow-key presses from the app's window even while
/// the otherwise-empty search field owns keyboard focus. Returning `nil`
/// from the local monitor prevents the field editor from consuming the same
/// key press afterward.
package struct ArrowKeyMonitor: NSViewRepresentable {
    package let isEnabled: Bool
    package let onArrowKey: (CalendarArrowKey) -> Void

    package func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.installMonitor()
        return view
    }

    package func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onArrowKey = onArrowKey
    }

    package func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onArrowKey: onArrowKey)
    }

    package static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    package final class Coordinator {
        package weak var hostView: NSView?
        package var isEnabled: Bool
        package var onArrowKey: (CalendarArrowKey) -> Void
        private var monitor: Any?

        package init(isEnabled: Bool, onArrowKey: @escaping (CalendarArrowKey) -> Void) {
            self.isEnabled = isEnabled
            self.onArrowKey = onArrowKey
        }

        package func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.isEnabled,
                      !ShortcutRecording.isRecording,
                      event.window === self.hostView?.window,
                      event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]),
                      let key = Self.arrowKey(for: event.keyCode) else {
                    return event
                }

                self.onArrowKey(key)
                return nil
            }
        }

        package func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private static func arrowKey(for keyCode: UInt16) -> CalendarArrowKey? {
            switch keyCode {
            case 123: return .left
            case 124: return .right
            case 125: return .down
            case 126: return .up
            default: return nil
            }
        }
    }

    package init(isEnabled: Bool, onArrowKey: @escaping (CalendarArrowKey) -> Void) {
        self.isEnabled = isEnabled
        self.onArrowKey = onArrowKey
    }
}
