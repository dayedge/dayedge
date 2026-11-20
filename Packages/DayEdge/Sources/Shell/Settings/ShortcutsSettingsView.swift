import SwiftUI
import Domain
import UI

/// Settings › Shortcuts: commands, which can be re-recorded inline, and
/// the navigation keys, which are fixed and only shown. Everything reads
/// `KeyboardShortcutSettings` — the same store key handling, menus and
/// tooltips use — so a change here is live everywhere at once.
struct ShortcutsSettingsView: View {
    private let settings = KeyboardShortcutSettings.shared
    private let global = CommandWindowShortcut.shared

    var body: some View {
        SettingsPane {
            if CommandWindowShortcut.isAvailable {
                SettingsGroup(header: L10n.tr("shortcutssettingsview.global", "Global"),
                              footer: L10n.tr("shortcutssettingsview.global.footer", "Works from any app.")) {
                    SettingsRow(title: Self.globalTitle) { globalRecorder }
                }
            }
            SettingsGroup(header: L10n.tr("shortcutssettingsview.commands", "Commands"),
                          footer: L10n.tr("shortcutssettingsview.commands.footer",
                                          "Click a shortcut, then press the new keys. ⌫ removes it, Esc cancels.")) {
                ForEach(PanelCommand.commands, id: \.id) { command in
                    SettingsRow(title: command.title) { recorder(for: command) }
                }
            }
            SettingsGroup(header: L10n.tr("shortcutssettingsview.navigation", "Navigation")) {
                ForEach(Self.navigation, id: \.title) { row in
                    SettingsRow(title: row.title) {
                        HStack(spacing: 4) {
                            ForEach(row.keys, id: \.self) { KeyboardShortcutKey($0) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            HStack {
                Spacer()
                Button(L10n.tr("shortcutssettingsview.restore.defaults", "Restore Defaults")) {
                    settings.resetAll()
                    global.reset()
                }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(!settings.hasCustomizations && !global.isCustomized)
            }
        }
    }

    private func recorder(for command: PanelCommand) -> some View {
        ShortcutRecorder(
            id: command.id,
            title: command.title,
            shortcut: settings.shortcut(for: command),
            isCustomized: settings.isCustomized(command),
            validate: { problem($0, for: command) },
            onAssign: { settings.set($0, for: command) },
            onClear: { settings.clear(command) },
            onReset: { settings.reset(command) }
        )
    }

    private static var globalTitle: String {
        L10n.tr("shortcutssettingsview.show.command.window", "Show Command Window")
    }

    /// A hot key takes its keys from every app, the panel included.
    private var globalRecorder: some View {
        ShortcutRecorder(
            id: CommandWindowShortcut.id,
            title: Self.globalTitle,
            shortcut: global.shortcut,
            isCustomized: global.isCustomized,
            validate: { problem($0, for: nil) },
            onAssign: { global.set($0) },
            onClear: { global.set(nil) },
            onReset: global.reset
        )
    }

    /// Why a key can't be `command`'s (nil: the global shortcut's), if it can't.
    private func problem(_ candidate: KeyboardCommand, for command: PanelCommand?) -> String? {
        if let ineligible = KeyboardShortcutSettings.eligibility(candidate) { return ineligible.message }
        if let owner = settings.collision(candidate, for: command) { return owner.usedMessage }
        return command != nil && candidate == global.shortcut ? ShortcutOwner.fixed(Self.globalTitle).usedMessage : nil
    }

    /// The fixed keys, as the app uses them (read from the registry where
    /// it names them).
    private static var navigation: [(title: String, keys: [String])] {
        func label(_ action: PanelAction) -> String {
            KeyboardShortcutSettings.shared.shortcut(for: .action(action))?.displayLabel ?? ""
        }
        return [
            (L10n.tr("shortcutssettingsview.move.between.items", "Move Between Items"), ["↑", "↓"]),
            (L10n.tr("shortcutssettingsview.previous.next.month.or.list", "Previous / Next Month or List"), ["←", "→"]),
            (L10n.tr("shortcutssettingsview.previous.next.day", "Previous / Next Day"), [label(.previousDay), label(.nextDay)]),
            (L10n.tr("shortcutssettingsview.previous.next.week", "Previous / Next Week"), [label(.previousWeek), label(.nextWeek)]),
            (L10n.tr("shortcutssettingsview.open.selected.item", "Open Selected Item"), [label(.openEventDetails)]),
            (PanelAction.completeSelectedTask.title, [label(.completeSelectedTask)]),
            (L10n.tr("shortcutssettingsview.show.search.result", "Show Search Result"), [PanelCommands.showSearchResult.displayLabel]),
            (PanelAction.escapeSearch.title, [label(.escapeSearch)])
        ]
    }
}
