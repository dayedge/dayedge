import AppKit

/// A borderless `NSWindow` can't become key by default, which would
/// silently defeat keyboard focus/typing (e.g. the search field) despite
/// SwiftUI-side focus requests. Overriding these two is the standard fix
/// for borderless/utility-style windows that still need real text input.
final class BubbleWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
