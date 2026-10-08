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
    /// beside the item (`KeyboardCommands` is the one registry).
    package var shortcut: KeyboardCommandAction? {
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
