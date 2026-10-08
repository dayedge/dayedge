import AppKit
import SwiftUI

/// The open details card's keys: ↑ / ↓ select a property, ↩ opens it, Esc
/// closes the card. The panel's shortcut monitor offers each key here right
/// after the decision card and before its own shortcuts — the layering is
/// editor/menu (their own windows, never reaching the monitor) → decision
/// → details → panel. Only presses in the card's own window, and never
/// while a text field there is being edited.
@MainActor
package final class DetailKeyboard {
    package static let shared = DetailKeyboard()

    package enum Key { case up, down, activate, close }

    private weak var window: NSWindow?
    /// True when the card used the key; false lets it through to the panel.
    private var handler: ((Key) -> Bool)?

    package func register(window: NSWindow, handler: @escaping (Key) -> Bool) {
        self.window = window
        self.handler = handler
    }

    package func unregister(window: NSWindow?) {
        guard window == nil || window === self.window else { return }
        self.window = nil
        handler = nil
    }

    /// True when the key was the card's.
    package func handle(_ event: NSEvent) -> Bool {
        guard let handler, let window, event.window === window, !ShortcutRecording.isRecording,
              !(window.firstResponder is NSTextView),
              event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
        switch event.keyCode {
        case 126: return handler(.up)
        case 125: return handler(.down)
        case 36, 76: return handler(.activate)
        case 53: return handler(.close)
        default: return false
        }
    }
}

/// Reports the window this view lives in (a details card's popover window).
package struct WindowReader: NSViewRepresentable {
    package let onWindow: (NSWindow?) -> Void

    package func makeNSView(context: Context) -> NSView { ReaderView(onWindow: onWindow) }
    package func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let onWindow: (NSWindow?) -> Void
        init(onWindow: @escaping (NSWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow(window)
        }
    }
}

extension View {
    /// Makes this details card the keyboard's while it's on screen.
    package func detailKeyboard(_ handler: @escaping (DetailKeyboard.Key) -> Bool) -> some View {
        modifier(DetailKeyboardModifier(handler: handler))
    }
}

private struct DetailKeyboardModifier: ViewModifier {
    let handler: (DetailKeyboard.Key) -> Bool
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window in
                self.window = window
                if let window { DetailKeyboard.shared.register(window: window, handler: handler) }
            })
            .onDisappear { DetailKeyboard.shared.unregister(window: window) }
    }
}
