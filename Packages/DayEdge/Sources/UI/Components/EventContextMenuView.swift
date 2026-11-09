import SwiftUI
import Domain

/// Renders one event's right-click menu from `EventContextMenuPlan`'s
/// pure classification; `EventActionCoordinator.perform` runs each item.
/// Native rows (`MenuRow`), with the panel's shortcut for the same action
/// shown beside it (shown, not registered — the panel runs it for the
/// selected event). On a search result, also search's Show in Calendar.
package struct EventContextMenuView: View {
    package let event: AgendaEventModel
    package let actions: EventActionCoordinator
    @Environment(\.searchResultReveal) private var searchResultReveal

    package var body: some View {
        Group {
            ForEach(Array(actions.menuActions(for: event, inSearch: searchResultReveal != nil).enumerated()), id: \.offset) { item in
                if case .divider = item.element {
                    Divider()
                } else {
                    MenuRow(title(item.element), symbol: item.element.symbolName,
                            role: item.element.isDestructive ? .destructive : nil,
                            shortcut: Self.shortcut(for: item.element)) {
                        if item.element == .showInCalendar { searchResultReveal?() } else { actions.perform(item.element, for: event) }
                    }
                }
            }
        }
        // The panel's tint (the theme's accent) would otherwise reach the
        // menu and colour its symbols; a native menu draws them like its text.
        .tint(nil)
    }

    private static func shortcut(for action: EventContextMenuAction) -> KeyboardShortcut? {
        if action == .showInCalendar { return PanelCommands.showSearchResult.swiftUIShortcut }
        return action.shortcut.flatMap { KeyboardShortcutSettings.shared.shortcut(for: .action($0))?.swiftUIShortcut }
    }

    private func title(_ action: EventContextMenuAction) -> String {
        EventContextMenuPlan.title(for: action, deletionAsks: actions.deletionAsks(event))
    }
}
