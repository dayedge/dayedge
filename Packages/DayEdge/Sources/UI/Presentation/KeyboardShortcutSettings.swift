import AppKit
import Observation

/// Why a key can't be a command's shortcut at all.
package enum ShortcutIneligibility: Equatable, Sendable {
    /// Plain, ⇧ or ⌥ keys type into the always-focused search field.
    case needsCommandOrControl
    /// A dead key, or one without a printable character.
    case unsupportedKey
    /// macOS or text editing needs it. (Other apps' and system-wide
    /// shortcuts can't be known reliably; nothing claims to detect them.)
    case reservedBySystem

    /// What the recorder says.
    package var message: String {
        switch self {
        case .needsCommandOrControl: return L10n.tr("shortcutrecorder.needs.modifier", "Add ⌘ or ⌃")
        case .unsupportedKey: return L10n.tr("shortcutrecorder.unsupported.key", "This key can't be used")
        case .reservedBySystem: return L10n.tr("shortcutrecorder.reserved", "Reserved by macOS")
        }
    }
}

/// Who already uses a key.
package enum ShortcutOwner: Equatable {
    case command(ShortcutCommand)
    case fixed(String)

    package var title: String {
        switch self {
        case .command(let command): return command.title
        case .fixed(let owner): return owner
        }
    }

    /// What the recorder says.
    package var usedMessage: String {
        L10n.tr("shortcutrecorder.used.by", "Already used for \(String(describing: title))")
    }
}

/// The one source of every shortcut: defaults in code (`ShortcutCommand`)
/// plus the user's overrides (UserDefaults, JSON, overrides only). Key
/// handling, menus, tooltips and Settings all read `shortcut(for:)` /
/// `resolve`. One key, one command, ever: overrides first, then defaults,
/// and anything already taken — by a fixed key or an earlier command —
/// is left unassigned rather than shared. A bad stored entry costs only
/// itself: it's ignored (and kept, if unknown), never the whole keyboard.
@MainActor
@Observable
package final class KeyboardShortcutSettings {
    package static let shared = KeyboardShortcutSettings()
    package nonisolated static let defaultsKey = "com.dayedge.shortcuts"
    /// What a stored entry says for "the user removed this shortcut".
    static let cleared = "none"

    package private(set) var effective: [ShortcutCommand: KeyboardCommand] = [:]
    /// The same, by key.
    private var bindings: [KeyboardCommand: ShortcutCommand] = [:]
    private var overrides: [String: Any] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    package init(defaults: UserDefaults = .standard, key: String = KeyboardShortcutSettings.defaultsKey) {
        self.defaults = defaults
        self.key = key
        overrides = Self.load(from: defaults, key: key)
        rebuild()
    }

    // MARK: Reading

    package func shortcut(for command: ShortcutCommand) -> KeyboardCommand? { effective[command] }

    package func isCustomized(_ command: ShortcutCommand) -> Bool { overrides[command.id] != nil }

    package var hasCustomizations: Bool { ShortcutCommand.commands.contains(where: isCustomized) }

    /// The command a key press runs in the panel, or nil — while a
    /// recorder listens, while a menu tracks (an open menu runs its own
    /// key equivalent, so nothing runs twice), for a one-shot command's
    /// auto-repeat, and for any key nothing is bound to (a cleared or moved
    /// shortcut never falls back to its old default).
    package func resolve(_ event: NSEvent, isRecording: Bool, isMenuTracking: Bool) -> ShortcutCommand? {
        guard !isRecording, !isMenuTracking, let pressed = KeyboardCommand(event: event),
              let command = bindings[pressed] else { return nil }
        return event.isARepeat && command.isConfigurable ? nil : command
    }

    /// `resolve` as the panel's key monitors call it (on the main thread).
    package nonisolated static func resolve(_ event: NSEvent) -> ShortcutCommand? {
        MainActor.assumeIsolated {
            shared.resolve(event, isRecording: ShortcutRecording.shared.isActive,
                           isMenuTracking: RunLoop.current.currentMode == .eventTracking)
        }
    }

    // MARK: Validation

    private static let reserved: Set<KeyboardCommand> = [
        KeyboardCommand(key: "q"), KeyboardCommand(key: "w"), KeyboardCommand(key: "h"),
        KeyboardCommand(key: "h", modifiers: [.command, .option]), KeyboardCommand(key: "m"),
        KeyboardCommand(keyCode: KeyCode.tab, modifiers: .command), KeyboardCommand(keyCode: KeyCode.space, modifiers: .command),
        KeyboardCommand(key: "`"),
        KeyboardCommand(key: "a"), KeyboardCommand(key: "c"), KeyboardCommand(key: "v"), KeyboardCommand(key: "x"),
        KeyboardCommand(key: "z"), KeyboardCommand(key: "z", modifiers: [.command, .shift]),
        KeyboardCommand(keyCode: KeyCode.delete, modifiers: .command)
    ]

    /// Can this key be a command's shortcut at all? (Conventional keys such
    /// as ⌘S are fine while nothing in DayEdge uses them.)
    package static func eligibility(_ shortcut: KeyboardCommand) -> ShortcutIneligibility? {
        if shortcut.key == nil && KeyboardCommand.specialKeyLabels[shortcut.keyCode ?? .max] == nil { return .unsupportedKey }
        guard !shortcut.modifiers.isDisjoint(with: [.command, .control]) else { return .needsCommandOrControl }
        return reserved.contains(shortcut) ? .reservedBySystem : nil
    }

    /// Who already uses this key in the panel, besides `command` itself.
    package func collision(_ shortcut: KeyboardCommand, for command: ShortcutCommand) -> ShortcutOwner? {
        if let other = bindings[shortcut], other != command { return .command(other) }
        return KeyboardCommands.fixedKeys.first { $0.shortcut == shortcut }.map { .fixed($0.owner) }
    }

    // MARK: Changing

    package func set(_ shortcut: KeyboardCommand, for command: ShortcutCommand) {
        guard command.isConfigurable, let data = try? JSONEncoder().encode(shortcut),
              let object = try? JSONSerialization.jsonObject(with: data) else { return }
        overrides[command.id] = object
        save()
    }

    /// No shortcut at all (stored, so a default never comes back by itself).
    package func clear(_ command: ShortcutCommand) {
        guard command.isConfigurable else { return }
        overrides[command.id] = Self.cleared
        save()
    }

    /// Back to the default.
    package func reset(_ command: ShortcutCommand) {
        overrides[command.id] = nil
        save()
    }

    /// Every command back to its default; nothing else is touched.
    package func resetAll() {
        for command in ShortcutCommand.commands { overrides[command.id] = nil }
        save()
    }

    // MARK: Storage

    private func save() {
        if overrides.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONSerialization.data(withJSONObject: overrides, options: [.sortedKeys]) {
            defaults.set(data, forKey: key)
        }
        rebuild()
    }

    /// Unknown ids are kept (a newer version may have written them);
    /// unreadable data counts as no overrides until the next change.
    private static func load(from defaults: UserDefaults, key: String) -> [String: Any] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// What's stored for a command.
    private enum Stored {
        /// Nothing usable: missing, or invalid — the default applies.
        case none
        /// The user removed the shortcut.
        case cleared
        case shortcut(KeyboardCommand)
    }

    private func stored(for command: ShortcutCommand) -> Stored {
        guard let value = overrides[command.id] else { return .none }
        if let text = value as? String, text == Self.cleared { return .cleared }
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let shortcut = try? JSONDecoder().decode(KeyboardCommand.self, from: data),
              Self.eligibility(shortcut) == nil else { return .none }
        return .shortcut(shortcut)
    }

    /// Fixed commands and keys first, then overrides, then defaults; a key
    /// already taken leaves the later command unassigned.
    private func rebuild() {
        var result: [ShortcutCommand: KeyboardCommand] = [:]
        var taken = Set(KeyboardCommands.fixedKeys.map(\.shortcut))
        func bind(_ command: ShortcutCommand, _ shortcut: KeyboardCommand?) {
            guard let shortcut, !taken.contains(shortcut) else { return }
            result[command] = shortcut
            taken.insert(shortcut)
        }
        for command in ShortcutCommand.allCases where !command.isConfigurable { bind(command, command.defaultShortcut) }
        let entries = ShortcutCommand.commands.map { ($0, stored(for: $0)) }
        for (command, entry) in entries {
            if case .shortcut(let shortcut) = entry { bind(command, shortcut) }
        }
        for (command, entry) in entries {
            if case .none = entry { bind(command, command.defaultShortcut) }
        }
        effective = result
        bindings = Dictionary(uniqueKeysWithValues: result.map { ($0.value, $0.key) })
    }
}
