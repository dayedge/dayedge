import Foundation
import Domain

/// One item in an event's right-click context menu. Deliberately
/// data-free except `.openLocationInMaps` — `.joinVideoCall`/
/// `.copyMeetingLink` don't carry a resolved URL, since resolving one
/// (`MeetingLink.preferredURL` consults `NSWorkspace` to see what's
/// installed) is an environment-dependent decision that belongs at click
/// time, not baked into this otherwise-pure plan.
package enum EventContextMenuAction: Hashable {
    case joinVideoCall
    case copyMeetingLink
    case openLocationInMaps(location: String)
    case previousOccurrence
    case nextOccurrence
    case muteReminders
    case restoreReminders
    case openInAppleCalendar
    /// Search results only: the result in DayEdge's calendar (Tab there).
    case showInCalendar
    case removeFromCalendar
    /// Delete (any event the app may delete; a repeating one asks which).
    case deleteEvent
    case divider

    /// Shown as destructive (red) wherever it's listed.
    package var isDestructive: Bool { self == .removeFromCalendar || self == .deleteEvent }

    /// The SF Symbol, as Calendar's menu would show it.
    package var symbolName: String? {
        switch self {
        case .joinVideoCall: return "video"
        case .copyMeetingLink: return "link"
        case .openLocationInMaps: return "map"
        case .openInAppleCalendar: return "calendar"
        case .showInCalendar: return ViewMode.day.symbolName
        case .nextOccurrence: return "arrow.right"
        case .previousOccurrence: return "arrow.left"
        case .muteReminders: return "bell.slash"
        case .restoreReminders: return "bell"
        case .removeFromCalendar, .deleteEvent: return "trash"
        case .divider: return nil
        }
    }

    /// The panel shortcut that does the same for the selected event, shown
    /// beside the item (`PanelCommands` is the one registry).
    package var shortcut: PanelAction? {
        switch self {
        case .joinVideoCall: return .joinSelectedMeeting
        case .copyMeetingLink: return .copySelectedMeetingLink
        case .openInAppleCalendar: return .openSelectedInCalendar
        case .nextOccurrence: return .nextOccurrence
        case .previousOccurrence: return .previousOccurrence
        default: return nil
        }
    }
}

/// Pure classification of what the app's right-click context menu should
/// contain for one event — no view code, no EventKit/NSWorkspace calls,
/// so it's fully deterministic and unit-testable. The app is a calendar
/// *companion*, not a management client: quick actions (Join, Copy Link,
/// Open Location) stay lightweight, and "Open in Apple Calendar" is the
/// escape hatch for what EventKit can't do — invites, responses, the repeat
/// rule. Destructive items: removing a genuinely cancelled event, and
/// deleting where `EventEditability` allows (editing is the popover's).
package enum EventContextMenuPlan {
    /// The item's title; Delete gets "…" when a decision follows it.
    package static func title(for action: EventContextMenuAction, deletionAsks: Bool) -> String { // swiftlint:disable:this cyclomatic_complexity - one case per menu action
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
            return deletionAsks
                ? L10n.tr("eventcontextmenuview.delete.event", "Delete Event…")
                : L10n.tr("eventcontextmenuview.delete.event.d45eff", "Delete Event")
        case .divider: return ""
        }
    }

    /// Calendar's grouping: the event's own actions, its occurrences (next
    /// first, as there), its alerts, then deleting — dividers only between
    /// groups that have something.
    /// `inSearch`: a search result, which can also be shown in DayEdge's
    /// calendar — before Open in Apple Calendar (in DayEdge, then outside).
    package static func actions(for event: AgendaEventModel, remindersMuted: Bool = false,
                                editability: EventEditability = .readOnly, inSearch: Bool = false) -> [EventContextMenuAction] {
        var eventActions: [EventContextMenuAction] = []
        if event.status != .cancelled {
            if event.meetingLink?.canJoin == true {
                eventActions += [.joinVideoCall, .copyMeetingLink]
            }
            if let location = event.subtitle, LocationMapsHeuristic.isLikelyMappableLocation(location) {
                eventActions.append(.openLocationInMaps(location: location))
            }
        }
        if inSearch { eventActions.append(.showInCalendar) }
        eventActions.append(.openInAppleCalendar)

        let occurrences: [EventContextMenuAction] = event.recurrenceReference != nil ? [.nextOccurrence, .previousOccurrence] : []
        let alerts: [EventContextMenuAction] = !event.isAllDay && event.reminderOccurrenceKey != nil
            ? [remindersMuted ? .restoreReminders : .muteReminders] : []
        let destructive: [EventContextMenuAction] = event.removalReference != nil ? [.removeFromCalendar]
            : editability.canDelete ? [.deleteEvent] : []

        return Array([eventActions, occurrences, alerts, destructive].filter { !$0.isEmpty }.joined(separator: [.divider]))
    }
}
