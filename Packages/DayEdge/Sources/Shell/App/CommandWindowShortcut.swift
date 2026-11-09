#if canImport(KeyboardShortcuts)
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⌃⌥D, from any app: show or hide the Command Window. Stored by the
    /// package (overrides only), ready for a Recorder row in Settings.
    static let toggleCommandWindow = Self("toggleCommandWindow", default: .init(.d, modifiers: [.control, .option]))
}
#endif

/// The app's one global shortcut. A system hot key: no event monitor, no
/// Accessibility permission. Only in Xcode builds (see `Package.swift`).
@MainActor
enum CommandWindowShortcut {
    /// Registers it once, at launch; `onPress` runs on every press.
    static func register(_ onPress: @escaping () -> Void) {
        #if canImport(KeyboardShortcuts)
        KeyboardShortcuts.onKeyDown(for: .toggleCommandWindow, action: onPress)
        #endif
    }
}
