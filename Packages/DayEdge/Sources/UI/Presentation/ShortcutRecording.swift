import AppKit
import Observation

/// Which shortcut is being recorded, if any. While one is, no DayEdge key
/// handler acts (`KeyboardShortcutSettings.resolve`, the palette, details
/// cards, decisions, the arrow and view keys check `isActive`) — the
/// recorder takes every key in its window.
@MainActor
@Observable
package final class ShortcutRecording {
    package static let shared = ShortcutRecording()

    package private(set) var active: ShortcutCommand?
    package var isActive: Bool { active != nil }

    package init() {}

    package func begin(_ command: ShortcutCommand) { active = command }

    /// Ends `command`'s recording (another one's is left alone).
    package func end(_ command: ShortcutCommand) {
        if active == command { active = nil }
    }

    /// For event monitors (on the main thread): whether any recorder listens.
    package nonisolated static var isRecording: Bool {
        MainActor.assumeIsolated { shared.isActive }
    }
}

/// What one key press does to a recording — pure, so it's tested without
/// a window.
package enum ShortcutRecorderDecision: Equatable {
    /// Esc: stop, keep the old shortcut.
    case cancel
    /// ⌫ (no modifiers): remove the shortcut.
    case clear
    case assign(KeyboardCommand)
    /// Not this key; keep listening and say why.
    case reject(String)

    package static func decide(_ event: NSEvent, validate: (KeyboardCommand) -> String?) -> ShortcutRecorderDecision {
        decide(keyCode: event.keyCode, baseCharacter: event.characters(byApplyingModifiers: []),
               modifierFlags: event.modifierFlags, validate: validate)
    }

    package static func decide(keyCode: UInt16, baseCharacter: String?, modifierFlags: NSEvent.ModifierFlags,
                               validate: (KeyboardCommand) -> String?) -> ShortcutRecorderDecision {
        let plain = KeyboardCommand.normalized(modifierFlags).isEmpty
        if keyCode == KeyCode.escape, plain { return .cancel }
        if keyCode == KeyCode.delete || keyCode == KeyCode.forwardDelete, plain { return .clear }
        guard let shortcut = KeyboardCommand(keyCode: keyCode, baseCharacter: baseCharacter, modifierFlags: modifierFlags) else {
            return .reject(ShortcutIneligibility.unsupportedKey.message)
        }
        if let problem = validate(shortcut) { return .reject(problem) }
        return .assign(shortcut)
    }
}
