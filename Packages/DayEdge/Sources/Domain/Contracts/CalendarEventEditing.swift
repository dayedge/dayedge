import Foundation

/// A new event, as the app chat proposes it.
package struct EventDraft: Equatable, Sendable {
    package var title: String
    package var start: Date
    package var end: Date
    package var isAllDay = false
    /// nil = the default calendar for new events.
    package var calendarIdentifier: String?
    package var location: String?
    package var notes: String?
    package var recurrenceRule: TaskRecurrenceRule?
    package var alerts: [EventAlert] = []
    /// Restoring a deleted event: everything else it had. Its alarms
    /// replace `alerts`. Nil for a new event.
    package var details: EventDetails?

    package init(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarIdentifier: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        recurrenceRule: TaskRecurrenceRule? = nil,
        alerts: [EventAlert] = [],
        details: EventDetails? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarIdentifier = calendarIdentifier
        self.location = location
        self.notes = notes
        self.recurrenceRule = recurrenceRule
        self.alerts = alerts
        self.details = details
    }
}

/// What changes on an existing occurrence; nil fields stay as they are.
/// An empty `location` or `notes` removes it.
package struct EventChange: Equatable, Sendable {
    package var title: String?
    package var start: Date?
    package var end: Date?
    package var isAllDay: Bool?
    package var location: String?
    package var notes: String?
    /// A new repeat rule (`.custom` is never written back).
    package var recurrence: TaskRecurrence?
    /// An exact repeat rule (Custom…, contextual presets) — wins over
    /// `recurrence`. Use `recurrence: .never` to stop repeating.
    package var recurrenceRule: TaskRecurrenceRule?
    /// All its time alerts, replaced.
    package var alerts: [EventAlert]?
    /// Move it to this (writable) calendar.
    package var calendarIdentifier: String?

    /// Alerts are personal: they may change on any event on a writable
    /// calendar, invitations included — nothing else may.
    package var isAlertsOnly: Bool {
        alerts != nil && title == nil && start == nil && end == nil && isAllDay == nil
            && location == nil && notes == nil && recurrence == nil && recurrenceRule == nil && calendarIdentifier == nil
    }

    package init(
        title: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool? = nil,
        location: String? = nil,
        notes: String? = nil,
        recurrence: TaskRecurrence? = nil,
        recurrenceRule: TaskRecurrenceRule? = nil,
        alerts: [EventAlert]? = nil,
        calendarIdentifier: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.recurrence = recurrence
        self.recurrenceRule = recurrenceRule
        self.alerts = alerts
        self.calendarIdentifier = calendarIdentifier
    }
}

/// A repeating event: this occurrence, or it and every later one —
/// Calendar's own two choices (EventKit's `.thisEvent` / `.futureEvents`).
package enum EventSpan: Hashable, Sendable {
    case thisEvent, futureEvents

}

/// What one of the app's writes touched — so the calendar index can refetch just
/// those months at once instead of waiting for EventKit's change signal.
/// Nil scope (unknown) means "something changed": refresh what's near.
package struct CalendarWriteScope: Equatable, Sendable {
    package var calendarIdentifiers: Set<String>
    package var ranges: [DateInterval]

    package static let userInfoKey = "DayEdge.calendarWriteScope"

    // swiftlint:disable:next large_tuple - labelled at every call site; a type would only wrap three values
    package typealias Occurrence = (calendar: String, start: Date, end: Date)

    /// A single occurrence before and after (either may be absent), or —
    /// for "this and future events" — everything from the earlier start on.
    package static func write(before: Occurrence?, after: Occurrence?, throughFuture: Bool) -> CalendarWriteScope {
        let parts = [before, after].compactMap { $0 }
        var ranges = parts.map { DateInterval(start: min($0.start, $0.end), end: max($0.start, $0.end)) }
        if throughFuture, let from = parts.map(\.start).min() {
            ranges = [DateInterval(start: from, end: .distantFuture)]
        }
        return CalendarWriteScope(calendarIdentifiers: Set(parts.map(\.calendar)), ranges: ranges)
    }
}

/// An occurrence as it was (or became) — what Undo puts back.
package struct EventSnapshot: Equatable, Sendable {
    package let eventIdentifier: String
    package let calendarIdentifier: String
    package let calendarTitle: String
    package let title: String
    package let start: Date
    package let end: Date
    package let isAllDay: Bool
    package let location: String?
    package let notes: String?
    package let hasAttendees: Bool
    package let isRecurring: Bool
    package var alerts: [EventAlert] = []
    /// What else it had — for putting it back (`draft`).
    package var details: EventDetails?

    package var reference: EventEditReference {
        EventEditReference(eventIdentifier: eventIdentifier, calendarIdentifier: calendarIdentifier,
                           occurrenceStart: start, occurrenceEnd: end, isWritable: true,
                           invitationFrom: nil, isInvitation: false, hasAttendees: hasAttendees)
    }

    /// The event again, as it was — for Undo of a delete.
    package var draft: EventDraft {
        EventDraft(title: title, start: start, end: end, isAllDay: isAllDay,
                   calendarIdentifier: calendarIdentifier, location: location, notes: notes,
                   alerts: alerts, details: details)
    }

    /// Undo of a delete recreates the event: everything in `draft` comes
    /// back, but to Calendar it's a new event — a new identifier and
    /// created date, and no attachments (EventKit can't read or write
    /// them). Attendees and repeat rules can't be recreated faithfully, so
    /// those deletions have no Undo (and ask first).
    package var canRecreate: Bool { !hasAttendees && !isRecurring }

    package init(
        eventIdentifier: String,
        calendarIdentifier: String,
        calendarTitle: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        hasAttendees: Bool,
        isRecurring: Bool,
        alerts: [EventAlert] = [],
        details: EventDetails? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.hasAttendees = hasAttendees
        self.isRecurring = isRecurring
        self.alerts = alerts
        self.details = details
    }
}

package struct WritableCalendar: Equatable, Sendable {
    package let identifier: String
    package let title: String
    package let isDefault: Bool
    /// Its color (`color` in views).
    package var tint: RGBAColor = .gray
    /// Its account ("iCloud", "Exchange") — the selector groups by it.
    package var group: String = ""

    package init(identifier: String, title: String, isDefault: Bool, tint: RGBAColor = .gray, group: String = "") {
        self.identifier = identifier
        self.title = title
        self.isDefault = isDefault
        self.tint = tint
        self.group = group
    }
}

package enum EventEditError: Error, Equatable {
    case notFound
    case notWritable
    case invitation(from: String?)
    case meeting
    case noCalendar(String?)

    package var message: String { message(locale: AppLocalization.displayLocale) }

    package func message(locale: Locale) -> String {
        switch self {
        case .notFound: return L10n.tr("calendareventediting.that.event.can.t.be.found.any.more", "That event can't be found any more.", locale: locale)
        case .notWritable: return L10n.tr("calendareventediting.that.calendar.can.t.be.changed", "That calendar can't be changed.", locale: locale)
        case .invitation(let organizer):
            if let organizer {
                return L10n.tr(
                    "event.error.invitation.from",
                    "It's an invitation from \(organizer); DayEdge doesn't change other people's meetings. Respond or change it in Apple Calendar.",
                    locale: locale
                )
            }
            return L10n.tr(
                "event.error.invitation",
                "It's an invitation; DayEdge doesn't change other people's meetings. Respond or change it in Apple Calendar.",
                locale: locale
            )
        case .meeting:
            return L10n.tr(
                "calendareventediting.it.s.a.meeting.with.f3afd3",
                "It's a meeting with attendees; change it in Apple Calendar so they're updated.",
                locale: locale
            )
        case .noCalendar(let name):
            return name.map { L10n.tr(
                "calendareventediting.there.s.no.calendar.called.211523",
                "There's no calendar called “\(String(describing: $0))” that can be changed.",
                locale: locale
            ) } ?? L10n.tr(
                "calendareventediting.there.s.no.calendar.for.new.events",
                "There's no calendar for new events.",
                locale: locale
            )
        }
    }
}

/// Event changes — from the event popover, its menu and the app chat.
/// Who may change what is `EventEditability`; the editor checks it again
/// at the moment of writing.
package protocol CalendarEventEditing: Sendable {
    func writableCalendars() async -> [WritableCalendar]
    func create(_ draft: EventDraft) async throws -> EventSnapshot
    /// Only the user's own events without attendees. Returns the occurrence
    /// before and after.
    func update(_ target: EventEditReference, _ change: EventChange, span: EventSpan) async throws -> (before: EventSnapshot, after: EventSnapshot)
    /// Any event on a writable calendar — invitations included (nobody is
    /// notified; the caller warns). Returns the occurrence as it was.
    func delete(_ target: EventEditReference, span: EventSpan) async throws -> EventSnapshot
}

extension CalendarEventEditing {
    package func update(_ target: EventEditReference, _ change: EventChange) async throws -> (before: EventSnapshot, after: EventSnapshot) {
        try await update(target, change, span: .thisEvent)
    }

    package func delete(_ target: EventEditReference) async throws -> EventSnapshot {
        try await delete(target, span: .thisEvent)
    }

    /// Undo of `create`: removes everything it made — for a repeating event
    /// the whole series (its reference is the first occurrence, so this and
    /// future events is all of them).
    @discardableResult
    package func undoCreate(_ created: EventSnapshot) async throws -> EventSnapshot {
        try await delete(created.reference, span: created.isRecurring ? .futureEvents : .thisEvent)
    }
}

extension Notification.Name {
    /// Calendar events changed and the new state is readable — what views,
    /// the menu bar and the Meeting HUD refresh on. Posted by the event
    /// source after the index commits (never raw `EKEventStoreChanged`,
    /// which arrives before the data is updated).
    package static let calendarEventsDidChange = Notification.Name("DayEdge.calendarEventsDidChange")
    /// The app itself wrote to the calendar (posted by its editors, with a
    /// `CalendarWriteScope` when the touched range is known).
    package static let calendarEventsWritten = Notification.Name("DayEdge.calendarEventsWritten")
}

extension CalendarWriteScope {
    /// Tell the event sources: refresh now, don't wait for macOS to say so.
    /// With a scope, the index refetches exactly what was touched.
    package static func announce(_ scope: CalendarWriteScope? = nil) {
        NotificationCenter.default.post(name: .calendarEventsWritten, object: nil,
                                        userInfo: scope.map { [CalendarWriteScope.userInfoKey: $0] })
    }
}
