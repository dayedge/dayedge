import CalendarIndex
import Foundation
import Domain

/// Enough of an occurrence to filter it and draw its month-grid dot.
package struct SourceMarker {
    package let calendarIdentifier: String
    package let startDate: Date
    /// `DeclinedEventFilter` semantics: an organizer cancellation is not a
    /// decline.
    package let isDeclinedByUser: Bool
    package let dotTint: RGBAColor
}

/// One occurrence as a `CalendarEventSource` hands it to `CalendarProvider`
/// for agenda/day reads; `makeModel` builds the full model only then.
package struct SourceEvent {
    package let marker: SourceMarker
    package let makeModel: () -> AgendaEventModel

    package var calendarIdentifier: String { marker.calendarIdentifier }
    package var startDate: Date { marker.startDate }
}

/// Where events come from — the only part that differs between sources.
/// `CalendarProvider` does everything the app shapes them into (month
/// grid, agenda sections, visibility and declined filtering) once, over
/// the source: `IndexedCalendarEventSource` (the local index); tests plug
/// in their own.
package protocol CalendarEventSource: AnyObject {
    var isAuthorized: Bool { get }

    /// Month-grid markers under every day they overlap within `window`.
    func markersByDaySync(in window: DateInterval, calendar: Calendar) -> [Date: [SourceMarker]]

    /// Events under every day (start of day) they overlap within `window`.
    /// For the synchronous `CalendarDataProviding` reads.
    func eventsByDaySync(in window: DateInterval, calendar: Calendar) -> [Date: [SourceEvent]]

    /// Same, never blocking the caller on a fetch.
    func eventsByDay(in window: DateInterval, calendar: Calendar) async -> [Date: [SourceEvent]]

    /// Every occurrence matching a search, in date order — ids and starts
    /// only (the request carries words, field words, range, calendars
    /// excluded and declined handling).
    func searchMatches(_ request: SearchRequest) -> [CalendarIndex.SearchMatch]

    /// Ranking candidates (best scored, nearest, nearest by title), with
    /// titles.
    func searchRanked(_ request: SearchRequest, now: Date) -> [CalendarIndex.RankedMatch]

    /// Full events for search matches, by id (the window a view shows).
    func events(matchIDs: [Int64]) -> [Int64: SourceEvent]
}

extension CalendarEventSource {
    package func searchMatches(_ request: SearchRequest) -> [CalendarIndex.SearchMatch] { [] }
    package func searchRanked(_ request: SearchRequest, now: Date) -> [CalendarIndex.RankedMatch] { [] }
    package func events(matchIDs: [Int64]) -> [Int64: SourceEvent] { [:] }
}

/// No index could be opened at all (see `CalendarIndexRuntime.make`): no
/// events, rather than a crash.
package final class UnavailableCalendarEventSource: CalendarEventSource {
    package init() {}

    package var isAuthorized: Bool { false }
    package func markersByDaySync(in window: DateInterval, calendar: Calendar) -> [Date: [SourceMarker]] { [:] }
    package func eventsByDaySync(in window: DateInterval, calendar: Calendar) -> [Date: [SourceEvent]] { [:] }
    package func eventsByDay(in window: DateInterval, calendar: Calendar) async -> [Date: [SourceEvent]] { [:] }
}

extension Domain.SearchMatch {
    package init(_ match: CalendarIndex.SearchMatch) {
        self.init(id: match.id, start: match.start, isAllDay: match.isAllDay)
    }
}

extension Domain.RankedMatch {
    package init(_ ranked: CalendarIndex.RankedMatch) {
        self.init(match: Domain.SearchMatch(ranked.match), title: ranked.title, rank: ranked.rank)
    }
}
