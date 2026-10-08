import Foundation

/// An occurrence read back from the index, with its calendar.
public struct IndexedOccurrence: Sendable, Hashable, Identifiable {
    /// The index row id — stable while the occurrence's `OccurrenceKey` is.
    public var id: Int64
    /// `"<calendarIdentifier>|<occurrenceKey>"`: app-level identity that
    /// also survives a rebuilt database.
    public var stableKey: String
    public var snapshot: OccurrenceSnapshot
    public var calendar: CalendarSnapshot
}

/// The minimum for month-grid dots — read without decoding payloads.
public struct DayMarker: Sendable, Hashable {
    public var occurrenceID: Int64
    public var calendarIdentifier: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var participation: ParticipationStatus?
    /// Nil until the row's month is refetched after the v2 migration.
    public var status: OccurrenceSnapshot.Status?
}

public struct SearchRequest: Sendable {
    /// Words matched anywhere (title, place, people, notes).
    public var text: String
    /// Words matched in the title only (`subject:`).
    public var titleText: String?
    /// Words matched in the organizer only (`from:`).
    public var organizer: String?
    /// Words matched among the people (`with:`).
    public var attendee: String?
    /// Only the user's own events (`from:me`).
    public var organizedByMe: Bool
    public var interval: DateInterval?
    /// Only these calendars, if set.
    public var includedCalendars: Set<String>?
    public var excludedCalendars: Set<String>
    public var includesDeclined: Bool
    public var limit: Int

    public init(text: String, titleText: String? = nil, organizer: String? = nil, attendee: String? = nil,
                organizedByMe: Bool = false, interval: DateInterval? = nil, includedCalendars: Set<String>? = nil,
                excludedCalendars: Set<String> = [], includesDeclined: Bool = true, limit: Int = 50) {
        self.text = text
        self.titleText = titleText
        self.organizer = organizer
        self.attendee = attendee
        self.organizedByMe = organizedByMe
        self.interval = interval
        self.includedCalendars = includedCalendars
        self.excludedCalendars = excludedCalendars
        self.includesDeclined = includesDeclined
        self.limit = limit
    }
}

/// One match of a search, without its payload: enough to place it on a
/// day; the full occurrence is loaded by `id` when shown.
public struct SearchMatch: Sendable, Hashable {
    public var id: Int64
    public var start: Date
    public var isAllDay: Bool

    public init(id: Int64, start: Date, isAllDay: Bool) {
        self.id = id
        self.start = start
        self.isAllDay = isAllDay
    }
}

/// A match with its title and text score (bm25 — lower is better), for
/// ranking without loading the occurrence.
public struct RankedMatch: Sendable, Hashable {
    public var match: SearchMatch
    public var title: String
    public var rank: Double

    public init(match: SearchMatch, title: String, rank: Double) {
        self.match = match
        self.title = title
        self.rank = rank
    }
}

public struct SearchHit: Sendable, Hashable {
    public var occurrence: IndexedOccurrence
    /// FTS5 bm25 — lower is better.
    public var rank: Double
}

/// How complete and fresh the data behind a read is.
public struct CoverageInfo: Sendable, Equatable {
    /// Months of the requested interval not yet indexed for every active
    /// calendar (empty = fully covered).
    public var missingMonths: [Date]
    /// Oldest refresh among the covered months, nil if nothing is covered.
    public var oldestFetch: Date?
    public var isRefreshing: Bool

    public var isComplete: Bool { missingMonths.isEmpty }
}

public struct ReadResult<Value: Sendable>: Sendable {
    public var value: Value
    public var coverage: CoverageInfo
    public var authorization: SourceAuthorization
}

/// Someone from the index's events, for completing `from:` / `with:`.
public struct IndexedPerson: Sendable, Hashable {
    public enum Role: Sendable {
        /// Who organized (`from:`).
        case organizer
        /// Who took part (`with:`).
        case attendee
    }

    public var name: String?
    public var email: String?
    /// How many live occurrences they're on.
    public var count: Int

    /// The name, else the email.
    public var displayName: String { name ?? email ?? "" }
}
