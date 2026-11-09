import AppKit
import SwiftUI
import Domain

/// One key and its modifiers — what a shortcut is, recorded and matched
/// the same way so it runs exactly as displayed:
/// - modifiers are only ⌘ ⌥ ⌃ ⇧ (Caps Lock, Fn, keypad bits never count);
/// - special keys (arrows, ↩, ⇥, Space, Esc, ⌫, F-keys…) by key code;
/// - every other key by its base character on the current layout (the key
///   itself, no modifiers applied): ⇧⌘2 is "⇧⌘2", not "⇧⌘@" — like menus,
///   a shortcut follows the layout's characters.
extension NSWindow {
    /// This window, or one of its child windows (a popover's, a picker's).
    package func isSelfOrChild(of window: NSWindow) -> Bool { self === window || parent === window }
}

/// Key codes the app names (hardware positions, the same on every layout).
package enum KeyCode {
    package static let leftArrow: UInt16 = 123
    package static let rightArrow: UInt16 = 124
    package static let downArrow: UInt16 = 125
    package static let upArrow: UInt16 = 126
    package static let returnKey: UInt16 = 36
    package static let keypadEnter: UInt16 = 76
    package static let tab: UInt16 = 48
    package static let space: UInt16 = 49
    package static let escape: UInt16 = 53
    package static let delete: UInt16 = 51
    package static let forwardDelete: UInt16 = 117
}

package struct KeyboardCommand: Hashable, Codable, Sendable {
    package var key: String?
    package var keyCode: UInt16?
    private var modifierBits: UInt

    package var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierBits) }

    package init(key: Character, modifiers: NSEvent.ModifierFlags = .command) {
        self.key = String(key).lowercased()
        self.keyCode = nil
        self.modifierBits = Self.normalized(modifiers).rawValue
    }

    package init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        self.key = nil
        self.keyCode = keyCode
        self.modifierBits = Self.normalized(modifiers).rawValue
    }

    /// The one normalising initialiser (pure): nil for a key that can't be
    /// a shortcut — a dead key, or one without a printable character.
    package init?(keyCode: UInt16, baseCharacter: String?, modifierFlags: NSEvent.ModifierFlags) {
        if Self.specialKeyLabels[keyCode] != nil {
            self.init(keyCode: keyCode, modifiers: modifierFlags)
            return
        }
        guard let base = baseCharacter, base.count == 1, let scalar = base.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.whitespacesAndNewlines.contains(scalar),
              !(0xF700...0xF8FF).contains(scalar.value) else { return nil }   // function-key private use
        self.init(key: Character(base), modifiers: modifierFlags)
    }

    /// From a key press: what the recorder stores and what `matches` compares.
    package init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        self.init(keyCode: event.keyCode, baseCharacter: event.characters(byApplyingModifiers: []),
                  modifierFlags: event.modifierFlags)
    }

    package static func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift])
    }

    /// Keys a shortcut names by key code, and how they're written.
    package static let specialKeyLabels: [UInt16: String] = [
        KeyCode.leftArrow: "←", KeyCode.rightArrow: "→", KeyCode.downArrow: "↓", KeyCode.upArrow: "↑",
        KeyCode.returnKey: "↩", KeyCode.keypadEnter: "⌤", KeyCode.tab: "⇥", KeyCode.space: "Space", KeyCode.escape: "Esc",
        KeyCode.delete: "⌫", KeyCode.forwardDelete: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]

    package var keyLabel: String {
        if let keyCode { return Self.specialKeyLabels[keyCode] ?? "" }
        return key?.uppercased() ?? ""
    }

    /// "⇧⌘C" — built from the binding itself, so it never drifts from it.
    package var displayLabel: String {
        var label = ""
        if modifiers.contains(.control) { label += "⌃" }
        if modifiers.contains(.option) { label += "⌥" }
        if modifiers.contains(.shift) { label += "⇧" }
        if modifiers.contains(.command) { label += "⌘" }
        return label + keyLabel
    }

    /// The same binding for a SwiftUI menu item, so a menu shows it with
    /// the system's glyphs and alignment; nil for keys a menu can't show.
    package var swiftUIShortcut: KeyboardShortcut? {
        let flags: [(NSEvent.ModifierFlags, EventModifiers)] = [(.command, .command), (.shift, .shift), (.option, .option), (.control, .control)]
        let modifiers = EventModifiers(flags.filter { self.modifiers.contains($0.0) }.map(\.1))
        if let key, let character = key.first { return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers) }
        let equivalents: [UInt16: KeyEquivalent] = [
            KeyCode.returnKey: .return, KeyCode.tab: .tab, KeyCode.space: .space, KeyCode.escape: .escape, KeyCode.delete: .delete,
            KeyCode.leftArrow: .leftArrow, KeyCode.rightArrow: .rightArrow, KeyCode.downArrow: .downArrow, KeyCode.upArrow: .upArrow
        ]
        return keyCode.flatMap { equivalents[$0] }.map { KeyboardShortcut($0, modifiers: modifiers) }
    }
}

/// Something the user can ask the panel to do — by its shortcut, a menu or
/// the Actions list (⌘K). `PanelCommand` adds the view switches.
package enum PanelAction: CaseIterable, Hashable {
    case newEvent
    case newTask
    case newChat
    case showActions
    /// Listed in Actions; its key (⌘,) is the app menu's, not the panel's.
    case openSettings
    case previousDay
    case nextDay
    case previousWeek
    case nextWeek
    case today
    case focusSearch
    case escapeSearch
    case openEventDetails
    case joinSelectedMeeting
    case copySelectedMeetingLink
    case openSelectedInCalendar
    case nextOccurrence
    case previousOccurrence
    case completeSelectedTask
    case openSortMenu

    package var title: String {
        switch self {
        case .newEvent: return L10n.tr("keyboardcommands.new.event", "New Event")
        case .newTask: return L10n.tr("keyboardcommands.new.task", "New Task")
        case .newChat: return L10n.tr("keyboardcommands.new.chat", "New Chat")
        case .showActions: return L10n.tr("keyboardcommands.show.actions", "Actions")
        case .openSettings: return L10n.tr("keyboardcommands.open.settings", "Settings…")
        case .previousDay: return L10n.tr("keyboardcommands.previous.day", "Previous Day")
        case .nextDay: return L10n.tr("keyboardcommands.next.day", "Next Day")
        case .previousWeek: return L10n.tr("keyboardcommands.previous.week", "Previous Week")
        case .nextWeek: return L10n.tr("keyboardcommands.next.week", "Next Week")
        case .today: return L10n.tr("keyboardcommands.go.to.today", "Go to Today")
        case .focusSearch: return L10n.tr("keyboardcommands.focus.search", "Focus Search")
        case .escapeSearch: return L10n.tr("keyboardcommands.clear.or.leave.search", "Clear or Leave Search")
        case .openEventDetails: return L10n.tr("keyboardcommands.open.event.details", "Open Event Details")
        case .joinSelectedMeeting: return L10n.tr("keyboardcommands.join.selected.meeting", "Join Selected Meeting")
        case .copySelectedMeetingLink: return L10n.tr("keyboardcommands.copy.meeting.link", "Copy Meeting Link")
        case .openSelectedInCalendar: return L10n.tr("keyboardcommands.open.in.calendar", "Open in Apple Calendar")
        case .nextOccurrence: return L10n.tr("keyboardcommands.go.to.next.occurrence", "Go to Next Occurrence")
        case .previousOccurrence: return L10n.tr("keyboardcommands.go.to.previous.occurrence", "Go to Previous Occurrence")
        case .completeSelectedTask: return L10n.tr("keyboardcommands.complete.selected.task", "Complete Selected Task")
        case .openSortMenu: return L10n.tr("keyboardcommands.sort.tasks", "Sort Tasks")
        }
    }

    /// Runs while a field is being typed in, the palette is open or Ask
    /// shows: leaving the field, Today, and the app's own commands (new
    /// things, Actions, Settings). The rest act on the calendar's selection.
    package var worksWhileEditing: Bool {
        switch self {
        case .focusSearch, .escapeSearch, .today, .newEvent, .newTask, .newChat, .showActions, .openSettings: true
        default: false
        }
    }

    /// Its SF Symbol, beside its title in the Actions list.
    package var symbolName: String {
        switch self {
        case .newEvent: return "calendar.badge.plus"
        case .newTask: return "checklist"
        case .newChat: return "bubble.left"
        case .showActions: return "command"
        case .openSettings: return "gearshape"
        case .previousDay, .previousWeek, .previousOccurrence: return "arrow.left"
        case .nextDay, .nextWeek, .nextOccurrence: return "arrow.right"
        case .today: return "calendar"
        case .focusSearch: return "magnifyingglass"
        case .escapeSearch: return "xmark"
        case .openEventDetails: return "info.circle"
        case .joinSelectedMeeting: return "video"
        case .copySelectedMeetingLink: return "link"
        case .openSelectedInCalendar: return "calendar"
        case .completeSelectedTask: return "checkmark.circle"
        case .openSortMenu: return "arrow.up.arrow.down"
        }
    }
}

/// Every shortcut the app owns, by one stable identity. Commands (⌘-style)
/// can be re-recorded in Settings; navigation keys can't.
package enum PanelCommand: Hashable, CaseIterable {
    case action(PanelAction)
    case viewMode(ViewMode)
    /// A Tasks Overview view, from anywhere: it opens Tasks on it.
    case taskView(TaskSmartView)

    package static let allCases: [PanelCommand] =
        PanelAction.allCases.map(PanelCommand.action) + ViewMode.allCases.map(PanelCommand.viewMode)
        + TaskSmartView.allCases.map(PanelCommand.taskView)

    /// The configurable ones, in Settings' order.
    package static let commands: [PanelCommand] = [
        .action(.newEvent), .action(.newTask), .action(.newChat), .action(.showActions),
        .action(.today), .action(.focusSearch),
        .viewMode(.month), .viewMode(.day), .viewMode(.tasks), .viewMode(.ask),
        .taskView(.attention), .taskView(.today), .taskView(.nextWeek), .taskView(.all),
        .action(.joinSelectedMeeting), .action(.copySelectedMeetingLink), .action(.openSelectedInCalendar),
        .action(.nextOccurrence), .action(.previousOccurrence), .action(.openSortMenu)
    ]

    /// Stored in the overrides; never change one.
    package var id: String {
        switch self {
        case .action(let action): return "action.\(action)"
        case .viewMode(let mode): return "viewMode.\(mode)"
        case .taskView(let view): return "taskView.\(view.rawValue)"
        }
    }

    package var symbolName: String {
        switch self {
        case .action(let action): return action.symbolName
        case .viewMode(let mode): return mode.symbolName
        case .taskView(let view): return view.symbolName
        }
    }

    package var title: String {
        switch self {
        case .action(let action): return action.title
        case .viewMode(let mode): return L10n.tr("keyboardcommands.switch.to", "Switch to \(String(describing: mode.tooltipTitle))")
        case .taskView(let view): return L10n.tr("keyboardcommands.show.task.view", "Show \(String(describing: view.title))")
        }
    }

    private static let configurable = Set(commands)

    /// Switches what the panel shows: a view mode or a Tasks view.
    package var isViewSwitch: Bool {
        switch self {
        case .viewMode, .taskView: true
        case .action: false
        }
    }

    /// A command (re-recordable, one-shot: a held key doesn't repeat it), or
    /// a navigation key (fixed, repeats).
    package var isConfigurable: Bool { Self.configurable.contains(self) }

    /// The binding the app ships with; nil = unassigned (Sort Tasks: ⌘S is
    /// Save everywhere else).
    package var defaultShortcut: KeyboardCommand? {
        switch self {
        case .viewMode(let mode): return PanelCommands.viewModeDefaults[mode]
        case .action(let action): return PanelCommands.actionDefaults[action]
        case .taskView(let view): return PanelCommands.taskViewDefaults[view]
        }
    }
}

/// The defaults, in code — `KeyboardShortcutSettings` adds the user's
/// overrides and is what everything reads; nothing reads these directly.
package enum PanelCommands {
    static let viewModeDefaults: [ViewMode: KeyboardCommand] = [
        .month: KeyboardCommand(key: "1"),
        .day: KeyboardCommand(key: "2"),
        .tasks: KeyboardCommand(key: "3"),
        .ask: KeyboardCommand(key: "4")
    ]

    /// ⌥⌘, beside the views' ⌘1–4: ⌥ alone (or ⇧⌥) types a character in
    /// the always-focused search field, and ⇧⌘3 / ⇧⌘4 are macOS screenshots.
    static let taskViewDefaults: [TaskSmartView: KeyboardCommand] = [
        .attention: KeyboardCommand(key: "1", modifiers: [.command, .option]),
        .today: KeyboardCommand(key: "2", modifiers: [.command, .option]),
        .nextWeek: KeyboardCommand(key: "3", modifiers: [.command, .option]),
        .all: KeyboardCommand(key: "4", modifiers: [.command, .option])
    ]

    /// Arrow and return keys use key codes, stable across layouts.
    static let actionDefaults: [PanelAction: KeyboardCommand] = [
        .newEvent: KeyboardCommand(key: "n"),
        .newTask: KeyboardCommand(key: "n", modifiers: [.command, .shift]),
        // Not ⌘N (New Event) nor ⇧⌘N (New Task); no common app owns it.
        .newChat: KeyboardCommand(key: "n", modifiers: [.command, .option]),
        .showActions: KeyboardCommand(key: "k"),
        .previousDay: KeyboardCommand(keyCode: KeyCode.leftArrow, modifiers: .shift),
        .nextDay: KeyboardCommand(keyCode: KeyCode.rightArrow, modifiers: .shift),
        .nextWeek: KeyboardCommand(keyCode: KeyCode.downArrow, modifiers: .shift),
        .previousWeek: KeyboardCommand(keyCode: KeyCode.upArrow, modifiers: .shift),
        .today: KeyboardCommand(key: "t"),
        .focusSearch: KeyboardCommand(key: "f"),
        .escapeSearch: KeyboardCommand(keyCode: KeyCode.escape),
        .openEventDetails: KeyboardCommand(keyCode: KeyCode.returnKey),
        .joinSelectedMeeting: KeyboardCommand(key: "j"),
        // The selected event's, as in Calendar (⌘[ / ⌘] between occurrences).
        // Never plain Delete: the search field is always focused, and a
        // Backspace too many would delete the selection.
        .copySelectedMeetingLink: KeyboardCommand(key: "c", modifiers: [.command, .shift]),
        .openSelectedInCalendar: KeyboardCommand(key: "o"),
        .nextOccurrence: KeyboardCommand(key: "]"),
        .previousOccurrence: KeyboardCommand(key: "["),
        .completeSelectedTask: KeyboardCommand(keyCode: KeyCode.space)
    ]

    /// ⌘Return: Create in Quick Add, Allow in Ask (with keypad Enter).
    package static let create = KeyboardCommand(keyCode: KeyCode.returnKey, modifiers: .command)
    package static let createOnKeypad = KeyboardCommand(keyCode: KeyCode.keypadEnter, modifiers: .command)

    /// Search's Tab: a result shown where it lives (the palette's own key,
    /// shown beside "Show in Calendar / Tasks" in a result's menu).
    package static let showSearchResult = KeyboardCommand(keyCode: KeyCode.tab)

    /// Keys other handlers own (the palette, details cards, decisions, Ask,
    /// Settings, the status menu) — fixed, but no command may take them.
    package struct FixedKey {
        package let shortcut: KeyboardCommand
        package let owner: String
    }

    /// Keys other panel handlers own (the arrows, the palette, Ask, the
    /// status menu's ⌘,) — fixed, and no command may take them. (Settings'
    /// own ⌘[ / ⌘] live in another window and don't count.)
    package static let fixedKeys: [FixedKey] = [KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.downArrow, KeyCode.upArrow].map {
        FixedKey(shortcut: KeyboardCommand(keyCode: $0), owner: L10n.tr("shortcuts.fixed.arrows", "Arrow keys"))
    } + [
        FixedKey(shortcut: showSearchResult, owner: L10n.tr("shortcuts.fixed.show.search.result", "Show search result")),
        FixedKey(shortcut: KeyboardCommand(keyCode: KeyCode.tab, modifiers: .shift),
                 owner: L10n.tr("shortcuts.fixed.quick.add.fields", "Quick Add fields")),
        FixedKey(shortcut: create, owner: L10n.tr("shortcuts.fixed.allow.change", "Create in Quick Add, Allow in Ask")),
        FixedKey(shortcut: KeyboardCommand(keyCode: KeyCode.delete, modifiers: .command), owner: L10n.tr("shortcuts.fixed.delete.in.ask", "Delete in Ask")),
        FixedKey(shortcut: KeyboardCommand(key: ","), owner: L10n.tr("shortcuts.fixed.settings", "Settings"))
    ]
}
