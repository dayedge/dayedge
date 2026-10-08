import SwiftUI
import Domain
import UI

/// Settings › Shortcuts: commands, which can be re-recorded inline, and
/// the navigation keys, which are fixed and only shown. Everything reads
/// `KeyboardShortcutSettings` — the same store key handling, menus and
/// tooltips use — so a change here is live everywhere at once.
struct ShortcutsSettingsView: View {
    private let settings = KeyboardShortcutSettings.shared

    var body: some View {
        SettingsPane {
            SettingsGroup(header: L10n.tr("shortcutssettingsview.commands", "Commands"),
                          footer: L10n.tr("shortcutssettingsview.commands.footer",
                                          "Click a shortcut, then press the new keys. ⌫ removes it, Esc cancels.")) {
                ForEach(ShortcutCommand.commands, id: \.id) { command in
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
                Button(L10n.tr("shortcutssettingsview.restore.defaults", "Restore Defaults")) { settings.resetAll() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(!settings.hasCustomizations)
            }
        }
    }

    private func recorder(for command: ShortcutCommand) -> some View {
        ShortcutRecorder(
            command: command,
            shortcut: settings.shortcut(for: command),
            isCustomized: settings.isCustomized(command),
            validate: { candidate in
                KeyboardShortcutSettings.eligibility(candidate)?.message ?? settings.collision(candidate, for: command)?.usedMessage
            },
            onAssign: { settings.set($0, for: command) },
            onClear: { settings.clear(command) },
            onReset: { settings.reset(command) }
        )
    }

    /// The fixed keys, as the app uses them (read from the registry where
    /// it names them).
    private static var navigation: [(title: String, keys: [String])] {
        func label(_ action: KeyboardCommandAction) -> String {
            KeyboardShortcutSettings.shared.shortcut(for: .action(action))?.displayLabel ?? ""
        }
        return [
            (L10n.tr("shortcutssettingsview.move.between.items", "Move Between Items"), ["↑", "↓"]),
            (L10n.tr("shortcutssettingsview.previous.next.month.or.list", "Previous / Next Month or List"), ["←", "→"]),
            (L10n.tr("shortcutssettingsview.previous.next.day", "Previous / Next Day"), [label(.previousDay), label(.nextDay)]),
            (L10n.tr("shortcutssettingsview.previous.next.week", "Previous / Next Week"), [label(.previousWeek), label(.nextWeek)]),
            (L10n.tr("shortcutssettingsview.open.selected.item", "Open Selected Item"), [label(.openEventDetails)]),
            (KeyboardCommandAction.completeSelectedTask.title, [label(.completeSelectedTask)]),
            (L10n.tr("shortcutssettingsview.show.search.result", "Show Search Result"), [KeyboardCommands.showSearchResult.displayLabel]),
            (KeyboardCommandAction.escapeSearch.title, [label(.escapeSearch)])
        ]
    }
}
