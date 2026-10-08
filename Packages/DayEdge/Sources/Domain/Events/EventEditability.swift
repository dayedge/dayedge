import Foundation

/// What the app may do to an event — the one rule set behind the event
/// popover, its right-click menu and the app chat.
///
/// EventKit can't add or remove invitees, answer an invitation, change the
/// organizer or notify anyone; Calendar does those. So the app edits only
/// the user's own events without attendees, and anything with people in it
/// is edited in Calendar. Deleting is allowed on any writable calendar, with
/// a warning where someone won't be told.
package enum EventEditability: Equatable, Sendable {
    /// The user's own event, no attendees, on a writable calendar.
    case editable
    /// The user's own meeting with attendees.
    case meeting
    /// Someone else's invitation.
    case invitation(organizer: String?)
    /// A calendar that can't be changed (holidays, subscriptions, shared
    /// without edit rights), a cancelled event, or no EventKit backing.
    case readOnly

    package static func of(_ event: AgendaEventModel) -> EventEditability {
        guard event.status != .cancelled, let reference = event.editReference, reference.isWritable else { return .readOnly }
        if reference.isInvitation { return .invitation(organizer: reference.invitationFrom) }
        if reference.hasAttendees { return .meeting }
        return .editable
    }

    package var canEdit: Bool { self == .editable }
    /// Alerts are personal — the user's own on any event they can save,
    /// invitations included (as in Calendar).
    package var canEditAlerts: Bool { self != .readOnly }
    package var canDelete: Bool { self != .readOnly }

    /// Said before deleting, where deleting tells nobody.
    package var deleteWarning: String? {
        switch self {
        case .meeting:
            return L10n.tr(
                "eventeditability.attendees.won.t.be.notified.to.ff56cc",
                "Attendees won't be notified. To cancel the meeting for everyone, delete it in Apple Calendar."
            )
        case .invitation(let organizer):
            return L10n.tr(
                "eventeditability.won.t.be.notified.to.decline.fecdbf",
                "\(String(describing: organizer ?? L10n.tr("event.organizer", "The organizer"))) won't be notified. To decline, respond in Apple Calendar."
            )
        case .editable, .readOnly:
            return nil
        }
    }

    /// Why the details can't be changed here.
    package var readOnlyReason: String? { readOnlyReason(locale: AppLocalization.displayLocale) }

    package func readOnlyReason(locale: Locale) -> String? {
        switch self {
        case .editable: return nil
        case .meeting: return L10n.tr(
            "eventeditability.a.meeting.with.attendees.edit.it.76e5a1", "A meeting with attendees — edit it in Apple Calendar so they're updated."
        )
        case .invitation(let organizer):
            if let organizer {
                return L10n.tr("event.invitation.from", "An invitation from \(organizer) — respond or change it in Apple Calendar.", locale: locale)
            }
            return L10n.tr("event.invitation", "An invitation — respond or change it in Apple Calendar.", locale: locale)
        case .readOnly: return nil
        }
    }
}
