import AppKit
import SwiftUI
import UI

/// The palette's keys while it shows results — taken before the text
/// field would use them (↑/↓ would move the caret, Tab would move focus):
///   list:      ↑ / ↓ choose, Tab refines (never leaves the palette); Return
///              (the field's submit) and ⌘Return create
///   refining:  ⌘Return creates from any field, its pickers included; plain
///              Return never creates — it goes to the focused control (opens
///              its picker) or text field; Tab / Shift-Tab walk the fields
///              in their explicit order (pickers keep their own keys)
/// Esc is the root's (it closes a picker, then collapses).
package struct PaletteKeyMonitor: NSViewRepresentable {
    package let isEnabled: Bool
    package let isRefining: Bool
    package let onMove: (Int) -> Void
    package let onRefine: () -> Void
    /// Refining: next (false) / previous (true) field.
    package let onTab: (Bool) -> Void
    /// ⌘Return: create, whatever has focus.
    package let onCreate: () -> Void

    package func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    package func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configuration = self
    }

    package func makeCoordinator() -> Coordinator { Coordinator(configuration: self) }

    package static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    package final class Coordinator {
        package weak var hostView: NSView?
        package var configuration: PaletteKeyMonitor
        private var monitor: Any?

        package init(configuration: PaletteKeyMonitor) {
            self.configuration = configuration
        }

        package func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.configuration.isEnabled, !ShortcutRecording.isRecording,
                      let window = self.hostView?.window, let eventWindow = event.window else { return event }
                if eventWindow.isSelfOrChild(of: window), Self.isCreate(event, in: eventWindow) {
                    self.configuration.onCreate()
                    return nil
                }
                guard eventWindow === window else { return event }
                return self.handle(event) ? nil : event
            }
        }

        package func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// ⌘Return — unless an input method is composing (it owns Return).
        private static func isCreate(_ event: NSEvent, in window: NSWindow) -> Bool {
            guard let key = KeyboardCommand(event: event), key == KeyboardCommands.create || key == KeyboardCommands.createOnKeypad
            else { return false }
            return !((window.firstResponder as? NSTextView)?.hasMarkedText() ?? false)
        }

        /// True when the key was the palette's.
        /// (Refining, everything but Tab — Return included — is the focused
        /// control's or text field's.)
        private func handle(_ event: NSEvent) -> Bool {
            let modifiers = KeyboardCommand.normalized(event.modifierFlags)
            let config = configuration
            switch (event.keyCode, modifiers) {
            case (KeyCode.tab, []) where config.isRefining: config.onTab(false)
            case (KeyCode.tab, .shift) where config.isRefining: config.onTab(true)
            case _ where config.isRefining: return false
            case (KeyCode.upArrow, []): config.onMove(-1)
            case (KeyCode.downArrow, []): config.onMove(1)
            case (KeyCode.tab, []): config.onRefine()   // refine, or nothing
            default: return false
            }
            return true
        }
    }
}
