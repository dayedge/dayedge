import Foundation

/// One calendar as EventKit describes it — plain values only.
public struct CalendarSnapshot: Sendable, Codable, Hashable {
    public enum SourceKind: String, Sendable, Codable {
        case local, exchange, calDAV, mobileMe, subscribed, birthdays, other
    }

    public struct RGBA: Sendable, Codable, Hashable {
        public var red, green, blue, alpha: Double
        public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }

    public var identifier: String
    public var title: String
    public var sourceIdentifier: String
    public var sourceTitle: String
    public var sourceKind: SourceKind
    public var color: RGBA
    public var allowsModifications: Bool

    public init(identifier: String, title: String, sourceIdentifier: String = "", sourceTitle: String = "",
                sourceKind: SourceKind = .other, color: RGBA = RGBA(red: 0.5, green: 0.5, blue: 0.5),
                allowsModifications: Bool = true) {
        self.identifier = identifier
        self.title = title
        self.sourceIdentifier = sourceIdentifier
        self.sourceTitle = sourceTitle
        self.sourceKind = sourceKind
        self.color = color
        self.allowsModifications = allowsModifications
    }
}

/// A participant's answer, mirroring `EKParticipantStatus`.
public enum ParticipationStatus: String, Sendable, Codable {
    case unknown, pending, accepted, declined, tentative, delegated, completed, inProcess
}

public struct AttendeeSnapshot: Sendable, Codable, Hashable {
    public var name: String?
    public var email: String?
    public var status: ParticipationStatus
    public var isCurrentUser: Bool

    public init(name: String?, email: String?, status: ParticipationStatus, isCurrentUser: Bool) {
        self.name = name
        self.email = email
        self.status = status
        self.isCurrentUser = isCurrentUser
    }
}

public struct OrganizerSnapshot: Sendable, Codable, Hashable {
    public var name: String?
    public var email: String?
    public var isCurrentUser: Bool

    public init(name: String?, email: String?, isCurrentUser: Bool) {
        self.name = name
        self.email = email
        self.isCurrentUser = isCurrentUser
    }
}

/// An alarm: relative to the start, or at an absolute date.
public struct AlarmSnapshot: Sendable, Codable, Hashable {
    public var relativeOffset: TimeInterval?
    public var absoluteDate: Date?
    /// A location ("when I arrive/leave") alarm — not a time alert.
    public var isLocationBased: Bool

    public init(relativeOffset: TimeInterval? = nil, absoluteDate: Date? = nil, isLocationBased: Bool = false) {
        self.relativeOffset = relativeOffset
        self.absoluteDate = absoluteDate
        self.isLocationBased = isLocationBased
    }

    private enum CodingKeys: String, CodingKey { case relativeOffset, absoluteDate, isLocationBased }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        relativeOffset = try c.decodeIfPresent(TimeInterval.self, forKey: .relativeOffset)
        absoluteDate = try c.decodeIfPresent(Date.self, forKey: .absoluteDate)
        isLocationBased = try c.decodeIfPresent(Bool.self, forKey: .isLocationBased) ?? false
    }
}

/// A plain mirror of `EKRecurrenceRule` — description only; EventKit does
/// all recurrence expansion, the index never computes occurrences.
public struct RecurrenceDescription: Sendable, Codable, Hashable {
    public enum Frequency: String, Sendable, Codable { case daily, weekly, monthly, yearly }

    public struct DayOfWeek: Sendable, Codable, Hashable {
        /// 1 = Sunday … 7 = Saturday, as `EKWeekday`.
        public var weekday: Int
        /// 0 = every such weekday; otherwise ±n-th in the period.
        public var weekNumber: Int
        public init(weekday: Int, weekNumber: Int = 0) {
            self.weekday = weekday
            self.weekNumber = weekNumber
        }
    }

    public enum End: Sendable, Codable, Hashable {
        case count(Int)
        case date(Date)
    }

    public var frequency: Frequency
    public var interval: Int
    public var daysOfWeek: [DayOfWeek]?
    public var daysOfMonth: [Int]?
    public var monthsOfYear: [Int]?
    public var weeksOfYear: [Int]?
    public var daysOfYear: [Int]?
    public var setPositions: [Int]?
    public var firstDayOfWeek: Int
    public var end: End?

    public init(frequency: Frequency, interval: Int = 1, daysOfWeek: [DayOfWeek]? = nil, daysOfMonth: [Int]? = nil,
                monthsOfYear: [Int]? = nil, weeksOfYear: [Int]? = nil, daysOfYear: [Int]? = nil,
                setPositions: [Int]? = nil, firstDayOfWeek: Int = 0, end: End? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.daysOfMonth = daysOfMonth
        self.monthsOfYear = monthsOfYear
        self.weeksOfYear = weeksOfYear
        self.daysOfYear = daysOfYear
        self.setPositions = setPositions
        self.firstDayOfWeek = firstDayOfWeek
        self.end = end
    }
}

/// One event occurrence as EventKit expanded it — everything the app's
/// agenda model needs, so plugging the index in as the display source
/// needs no schema change.
///
/// Stored as the row's JSON payload. **Forward compatibility rule:** a
/// field added later must decode when absent (optional, or defaulted in
/// `init(from:)` below) — old rows are read until their month refreshes.
public struct OccurrenceSnapshot: Sendable, Codable, Hashable {
    public enum Status: String, Sendable, Codable { case none, confirmed, tentative, canceled }
    public enum Availability: String, Sendable, Codable { case notSupported, busy, free, tentative, unavailable }

    // Identity (lookup references — the index's own key is `OccurrenceKey`).
    public var calendarIdentifier: String
    public var eventIdentifier: String?
    public var calendarItemIdentifier: String
    public var externalIdentifier: String?
    /// EventKit's `occurrenceDate`, as is: for a repeating occurrence its
    /// *original* date (unchanged when that one occurrence is moved); for a
    /// single event EventKit reports its start. `OccurrenceKey` reads it
    /// only for repeating events.
    public var occurrenceDate: Date?

    // Time.
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var timeZone: String?

    // Text.
    public var title: String
    public var location: String?
    public var notes: String?
    public var url: String?

    // People.
    public var attendees: [AttendeeSnapshot]
    public var organizer: OrganizerSnapshot?

    // State.
    public var status: Status
    /// The current user's own answer, if they're an attendee.
    public var participation: ParticipationStatus?
    public var availability: Availability

    // Repeats.
    /// Part of a series by any sign: its own rule, detached, or an
    /// Exchange "/RID=" item. Decides whether `OccurrenceKey` has a date.
    public var isRecurring: Bool
    public var isDetached: Bool
    /// EventKit's `hasRecurrenceRules` — the event's own rule, not the
    /// series' (the app's model tells the two apart).
    public var hasOwnRecurrenceRules: Bool
    /// The event's own rule, or its series' rule for a detached occurrence.
    public var recurrence: RecurrenceDescription?

    public var alarms: [AlarmSnapshot]

    // Editing facts.
    public var hasAttendees: Bool
    public var isInvitation: Bool

    public var created: Date?
    public var modified: Date?

    public init(calendarIdentifier: String, eventIdentifier: String? = nil, calendarItemIdentifier: String,
                externalIdentifier: String? = nil, occurrenceDate: Date? = nil,
                start: Date, end: Date, isAllDay: Bool = false, timeZone: String? = nil,
                title: String, location: String? = nil, notes: String? = nil, url: String? = nil,
                attendees: [AttendeeSnapshot] = [], organizer: OrganizerSnapshot? = nil,
                status: Status = .none, participation: ParticipationStatus? = nil, availability: Availability = .busy,
                isRecurring: Bool = false, isDetached: Bool = false, hasOwnRecurrenceRules: Bool = false,
                recurrence: RecurrenceDescription? = nil,
                alarms: [AlarmSnapshot] = [], hasAttendees: Bool? = nil, isInvitation: Bool = false,
                created: Date? = nil, modified: Date? = nil) {
        self.calendarIdentifier = calendarIdentifier
        self.eventIdentifier = eventIdentifier
        self.calendarItemIdentifier = calendarItemIdentifier
        self.externalIdentifier = externalIdentifier
        self.occurrenceDate = occurrenceDate
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZone = timeZone
        self.title = title
        self.location = location
        self.notes = notes
        self.url = url
        self.attendees = attendees
        self.organizer = organizer
        self.status = status
        self.participation = participation
        self.availability = availability
        self.isRecurring = isRecurring
        self.isDetached = isDetached
        self.hasOwnRecurrenceRules = hasOwnRecurrenceRules
        self.recurrence = recurrence
        self.alarms = alarms
        self.hasAttendees = hasAttendees ?? !attendees.isEmpty
        self.isInvitation = isInvitation
        self.created = created
        self.modified = modified
    }

    private enum CodingKeys: String, CodingKey {
        case calendarIdentifier, eventIdentifier, calendarItemIdentifier, externalIdentifier, occurrenceDate
        case start, end, isAllDay, timeZone, title, location, notes, url, attendees, organizer
        case status, participation, availability, isRecurring, isDetached, hasOwnRecurrenceRules, recurrence, alarms
        case hasAttendees, isInvitation, created, modified
    }

    /// Only identity and time are required; everything else defaults, so
    /// payloads written by an older build keep decoding.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calendarIdentifier = try c.decode(String.self, forKey: .calendarIdentifier)
        eventIdentifier = try c.decodeIfPresent(String.self, forKey: .eventIdentifier)
        calendarItemIdentifier = try c.decode(String.self, forKey: .calendarItemIdentifier)
        externalIdentifier = try c.decodeIfPresent(String.self, forKey: .externalIdentifier)
        occurrenceDate = try c.decodeIfPresent(Date.self, forKey: .occurrenceDate)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        attendees = try c.decodeIfPresent([AttendeeSnapshot].self, forKey: .attendees) ?? []
        organizer = try c.decodeIfPresent(OrganizerSnapshot.self, forKey: .organizer)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .none
        participation = try c.decodeIfPresent(ParticipationStatus.self, forKey: .participation)
        availability = try c.decodeIfPresent(Availability.self, forKey: .availability) ?? .busy
        isRecurring = try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        isDetached = try c.decodeIfPresent(Bool.self, forKey: .isDetached) ?? false
        hasOwnRecurrenceRules = try c.decodeIfPresent(Bool.self, forKey: .hasOwnRecurrenceRules) ?? false
        recurrence = try c.decodeIfPresent(RecurrenceDescription.self, forKey: .recurrence)
        alarms = try c.decodeIfPresent([AlarmSnapshot].self, forKey: .alarms) ?? []
        hasAttendees = try c.decodeIfPresent(Bool.self, forKey: .hasAttendees) ?? !attendees.isEmpty
        isInvitation = try c.decodeIfPresent(Bool.self, forKey: .isInvitation) ?? false
        created = try c.decodeIfPresent(Date.self, forKey: .created)
        modified = try c.decodeIfPresent(Date.self, forKey: .modified)
    }

    /// The searchable attendee text: names and addresses, one per line.
    /// The organizer's name and email, for `from:`; nil without one.
    var organizerText: String? {
        guard let organizer else { return nil }
        let parts = [organizer.name, organizer.email].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    var attendeesText: String {
        var parts: [String] = []
        if let organizer {
            parts += [organizer.name, organizer.email].compactMap { $0 }
        }
        for attendee in attendees {
            parts += [attendee.name, attendee.email].compactMap { $0 }
        }
        return parts.joined(separator: "\n")
    }
}

/// What the store writes with each snapshot. Bump when the *mapping* of
/// EventKit into snapshots changes (a new field filled in): rows written
/// by an older version count as changed on their month's next refresh,
/// with no migration and no rescan.
public enum SnapshotFormat {
    /// 2: raw `occurrenceDate`, `hasOwnRecurrenceRules`, location alarms
    /// flagged, the app's exact attendee email rule, attendees in a fixed
    /// order (EventKit's changes between fetches).
    public static let version = 2
}
