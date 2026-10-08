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
                            role: Self.isDestructive(item.element) ? .destructive : nil,
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
        if action == .showInCalendar { return KeyboardCommands.showSearchResult.swiftUIShortcut }
        return action.shortcut.flatMap { KeyboardShortcutSettings.shared.shortcut(for: .action($0))?.swiftUIShortcut }
    }

    private static func isDestructive(_ action: EventContextMenuAction) -> Bool {
        action == .removeFromCalendar || action == .deleteEvent
    }

    // swiftlint:disable:next cyclomatic_complexity - one case per menu action
    private func title(_ action: EventContextMenuAction) -> String {
        switch action {
        case .joinVideoCall: return L10n.tr("eventcontextmenuview.join", "Join")
        case .copyMeetingLink: return L10n.tr("eventcontextmenuview.copy.link", "Copy Link")
        case .openLocationInMaps: return L10n.tr("eventcontextmenuview.show.in.maps", "Show in Maps")
        case .showInCalendar: return L10n.tr("eventcontextmenuview.show.in.calendar", "Show in Calendar")
        // External, like "Open in Reminders"; "Show in …" stays for
        // navigation inside the app.
        case .openInAppleCalendar: return L10n.tr("eventcontextmenuview.open.in.calendar", "Open in Apple Calendar")
        case .nextOccurrence: return L10n.tr("eventcontextmenuview.go.to.next.occurrence", "Go to Next Occurrence")
        case .previousOccurrence: return L10n.tr("eventcontextmenuview.go.to.previous.occurrence", "Go to Previous Occurrence")
        // "Alerts", not "Reminders": Reminders are the tasks.
        case .muteReminders: return L10n.tr("eventcontextmenuview.mute.event.alerts", "Mute Event Alerts")
        case .restoreReminders: return L10n.tr("eventcontextmenuview.unmute.event.alerts", "Unmute Event Alerts")
        // Ellipsis: a confirmation follows (a small panel near the cursor).
        case .removeFromCalendar: return L10n.tr("eventcontextmenuview.remove.from.calendar", "Remove from Calendar…")
        // "…" when a decision follows; a plain delete just happens (Undo).
        case .deleteEvent:
            return actions.deletionAsks(event)
                ? L10n.tr("eventcontextmenuview.delete.event", "Delete Event…")
                : L10n.tr("eventcontextmenuview.delete.event.d45eff", "Delete Event")
        case .divider: return ""
        }
    }
}
