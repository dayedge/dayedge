import Foundation

/// One dated section in the scrollable agenda; its header is written from
/// `date` ("MONDAY 14 SEP").
package struct AgendaDaySection: Identifiable, Hashable {
    package let id: Date
    package let date: Date
    package let events: [AgendaEventModel]
    package let isToday: Bool

    package init(date: Date, events: [AgendaEventModel], isToday: Bool = false) {
        self.id = date
        self.date = date
        self.events = events
        self.isToday = isToday
    }
}

package struct AgendaEventModel: Identifiable, Hashable {
    /// Stable across rebuilds — for real events this is EventKit's own
    /// `eventIdentifier`, not a freshly-generated UUID. A random UUID
    /// here would make every event look "new" to SwiftUI on every
    /// `reload()`, forcing a full re-diff/re-render of the agenda list
    /// even when nothing actually changed.
    package let id: String
    package let startTime: String?
    package let endTime: String?
    /// Real, absolute start/end instants — distinct from `startTime`/
    /// `endTime`, which are pre-formatted `"HH:mm"` *display* strings
    /// with no date, time zone, or seconds. Anything that needs to
    /// reason about *when* an event actually is (the Meeting HUD, in
    /// particular) should use these, not reconstruct a `Date` from the
    /// display strings. `nil` for mock data / anything that hasn't been
    /// updated to populate them.
    package let startDate: Date?
    package let endDate: Date?
    package let title: String
    package let subtitle: String?
    package let status: EventStatus
    package let videoService: VideoConferenceService?
    package let hasLinkIcon: Bool
    package let isRecurring: Bool
    /// The owning calendar's color (`color` in views). Defaults to the
    /// theme's dot color so mock data (which has no real calendar behind
    /// it) still renders.
    package let tint: RGBAColor
    /// The rest are only used by the event-detail popover — absent
    /// (empty/nil) for mock data, which has no real calendar behind it.
    package let calendarName: String
    package let notes: String?
    package let videoURL: String?
    package let attendees: [EventAttendee]
    /// Your own RSVP, distinct from the per-attendee list — nil when
    /// there's no participant record for you (e.g. you organized it with
    /// no attendees, or it's mock data).
    package let myResponseStatus: EventAttendee.Status?
    /// Who organized it, when EventKit says (nil for your own events with
    /// no invitees, and for mock data).
    package let organizerName: String?
    /// When the event (for a repeating one: its series) was created and
    /// last changed, as the calendar server reports; nil when it doesn't.
    package let createdAt: Date?
    package let modifiedAt: Date?
    /// Present only when this exact occurrence is safe to remove: the
    /// underlying `EKEvent.status` is genuinely `.canceled` (not merely
    /// declined by the user — see `CalendarEventMapper.eventStatus(for:)`,
    /// which maps both to this model's `.cancelled` case), its calendar is
    /// user-modifiable, and it has a real identifier. `nil` always means
    /// "cannot remove" — there's no separate boolean defaulting to `true`.
    package let removalReference: EventRemovalReference?
    /// `EKEvent.calendarItemIdentifier` — the identifier the undocumented
    /// `ical://ekevent/...` Calendar.app deep link requires. Deliberately
    /// distinct from `EventRemovalReference.eventIdentifier`: that's
    /// `EKEvent.eventIdentifier`, a different EventKit identity used for a
    /// different purpose (re-locating an occurrence to remove it). Never
    /// conflate the two — see `AppleCalendarBridge`.
    package let calendarItemIdentifier: String?
    /// `EKEvent.occurrenceDate` — `nil` for a non-recurring event (its
    /// `startDate` is sufficient there), but for a recurring event this
    /// identifies *which* occurrence, distinctly from `startDate` (which
    /// can differ from the occurrence's original time if it was
    /// detached/moved).
    package let occurrenceDate: Date?
    /// Stable the app-only identity used for per-occurrence reminder state.
    /// `nil` when a real source identity is unavailable (for example mocks).
    package let reminderOccurrenceKey: ReminderOccurrenceKey?
    /// Present when EventKit can identify this recurring series reliably.
    /// Context-menu navigation uses this rather than matching titles.
    package let recurrenceReference: RecurringSeriesReference?
    /// For changing it from the app chat; nil when it can't be found again.
    package let editReference: EventEditReference?
    /// Its repeat rule, in the Repeat menu's terms (`.never` for a single event).
    package let recurrence: TaskRecurrence
    /// The exact rule (the Repeat editor's starting point); nil = none.
    package let recurrenceRule: TaskRecurrenceRule?
    /// Its time alerts, in order.
    package let alerts: [EventAlert]

    package init(id: String = UUID().uuidString, startTime: String? = nil, endTime: String? = nil,
                 startDate: Date? = nil, endDate: Date? = nil, title: String,
                 subtitle: String? = nil, status: EventStatus = .confirmed,
                 videoService: VideoConferenceService? = nil, hasLinkIcon: Bool = false, isRecurring: Bool = false,
                 tint: RGBAColor = .placeholder, calendarName: String = "", notes: String? = nil,
                 videoURL: String? = nil, attendees: [EventAttendee] = [], myResponseStatus: EventAttendee.Status? = nil,
                 removalReference: EventRemovalReference? = nil,
                 calendarItemIdentifier: String? = nil, occurrenceDate: Date? = nil,
                 reminderOccurrenceKey: ReminderOccurrenceKey? = nil,
                 recurrenceReference: RecurringSeriesReference? = nil,
                 organizerName: String? = nil, createdAt: Date? = nil, modifiedAt: Date? = nil,
                 editReference: EventEditReference? = nil,
                 recurrence: TaskRecurrence = .never, recurrenceRule: TaskRecurrenceRule? = nil, alerts: [EventAlert] = []) {
        self.editReference = editReference
        self.recurrence = recurrence
        self.recurrenceRule = recurrenceRule
        self.alerts = alerts
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.startDate = startDate
        self.endDate = endDate
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.videoService = videoService
        self.hasLinkIcon = hasLinkIcon
        self.isRecurring = isRecurring
        self.tint = tint
        self.calendarName = calendarName
        self.notes = notes
        self.videoURL = videoURL
        self.attendees = attendees
        self.myResponseStatus = myResponseStatus
        self.removalReference = removalReference
        self.calendarItemIdentifier = calendarItemIdentifier
        self.occurrenceDate = occurrenceDate
        self.reminderOccurrenceKey = reminderOccurrenceKey
        self.recurrenceReference = recurrenceReference
        self.organizerName = organizerName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// EventKit reports no start/end time string for an all-day event.
    package var isAllDay: Bool { startTime == nil && endTime == nil }

    /// Minutes since midnight, parsed from the "HH:mm" display strings.
    /// The agenda list only ever needs the display strings, but the day
    /// timeline needs actual numbers to position event blocks.
    package var startMinutesSinceMidnight: Int? { Self.minutes(from: startTime) }
    package var endMinutesSinceMidnight: Int? { Self.minutes(from: endTime) }

    private static func minutes(from time: String?) -> Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }
}

package enum EventStatus: Hashable {
    /// Solid dot — a confirmed, currently-relevant event.
    case confirmed
    /// Hollow/dashed dot — tentative or an alternate calendar source.
    case tentative
    /// Struck-through title, dimmed — a cancelled event.
    case cancelled
    /// No time range, just a placeholder title (e.g. "(no title)").
    case untimed
}

extension AgendaEventModel {
    /// Start and end as the user reads times (`TimeFormat`); the stored
    /// strings only for data without real dates (mock/legacy).
    package func startText(_ format: TimeFormat, calendar: Calendar = .autoupdatingCurrent) -> String? {
        startDate.map { format.time($0, calendar: calendar) } ?? startTime
    }

    package func endText(_ format: TimeFormat, calendar: Calendar = .autoupdatingCurrent) -> String? {
        endDate.map { format.time($0, calendar: calendar) } ?? endTime
    }

    /// "10:30 – 10:55" / "10:30–10:55am".
    package func rangeText(_ format: TimeFormat, calendar: Calendar = .autoupdatingCurrent) -> String? {
        if let startDate, let endDate { return format.range(startDate, endDate, calendar: calendar) }
        guard let startTime, let endTime else { return nil }
        return "\(startTime) – \(endTime)"
    }
}
