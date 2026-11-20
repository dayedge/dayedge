import Observation
import UI
#if canImport(KeyboardShortcuts)
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⌃⌥D, from any app: show or hide the Command Window. Stored by the
    /// package (`KeyboardShortcuts_toggleCommandWindow`).
    static let toggleCommandWindow = Self("toggleCommandWindow", default: .init(.d, modifiers: [.control, .option]))
}
#endif

/// The app's one global shortcut. A system hot key: no event monitor, no
/// Accessibility permission. Only in Xcode builds (see `Package.swift`).
/// Settings records it with the panel's `ShortcutRecorder`.
@MainActor
@Observable
final class CommandWindowShortcut {
    static let shared = CommandWindowShortcut()
    /// For `ShortcutRecording`.
    static let id = "global.toggleCommandWindow"

    /// Settings shows it only where the hot key exists.
    static var isAvailable: Bool {
        #if canImport(KeyboardShortcuts)
        true
        #else
        false
        #endif
    }

    private(set) var shortcut: KeyboardCommand?
    var isCustomized: Bool { shortcut != Self.defaultShortcut }

    private init() { refresh() }

    /// Registers it once, at launch; `onPress` runs on every press.
    func register(_ onPress: @escaping () -> Void) {
        #if canImport(KeyboardShortcuts)
        KeyboardShortcuts.onKeyDown(for: .toggleCommandWindow, action: onPress)
        pauseWhileRecording()
        #endif
    }

    /// nil: no shortcut at all (stored, so the default never comes back by itself).
    func set(_ shortcut: KeyboardCommand?) {
        #if canImport(KeyboardShortcuts)
        let hotKey = shortcut.flatMap(Self.hotKey)
        if shortcut != nil, hotKey == nil { return }
        KeyboardShortcuts.setShortcut(hotKey, for: .toggleCommandWindow)
        refresh()
        #endif
    }

    /// Back to ⌃⌥D.
    func reset() {
        #if canImport(KeyboardShortcuts)
        KeyboardShortcuts.reset(.toggleCommandWindow)
        refresh()
        #endif
    }

    private func refresh() {
        #if canImport(KeyboardShortcuts)
        shortcut = KeyboardShortcuts.getShortcut(for: .toggleCommandWindow).flatMap(Self.command)
        #endif
    }

    private static var defaultShortcut: KeyboardCommand? {
        #if canImport(KeyboardShortcuts)
        KeyboardShortcuts.Name.toggleCommandWindow.defaultShortcut.flatMap(command)
        #else
        nil
        #endif
    }

    #if canImport(KeyboardShortcuts)
    /// A system hot key takes its keys before any window: off while a
    /// recorder listens, so recording the current key (or a panel command
    /// on it) reaches the recorder.
    private func pauseWhileRecording() {
        withObservationTracking {
            KeyboardShortcuts.isEnabled = !ShortcutRecording.shared.isActive
        } onChange: { [weak self] in
            Task { @MainActor in self?.pauseWhileRecording() }
        }
    }

    /// Hot keys are physical keys; `KeyboardCommand` names a character in
    /// the current layout.
    private static func command(_ hotKey: KeyboardShortcuts.Shortcut) -> KeyboardCommand? {
        KeyboardCommand(keyCode: UInt16(hotKey.carbonKeyCode), baseCharacter: hotKey.nsMenuItemKeyEquivalent,
                        modifierFlags: hotKey.modifiers)
    }

    private static func hotKey(for shortcut: KeyboardCommand) -> KeyboardShortcuts.Shortcut? {
        let keyCode = shortcut.keyCode.map(Int.init) ?? (0..<128).first { code in
            command(KeyboardShortcuts.Shortcut(carbonKeyCode: code))?.key == shortcut.key
        }
        return keyCode.map { KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: $0), modifiers: shortcut.modifiers) }
    }
    #endif
}
