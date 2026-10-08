import Foundation

/// What the views and view models read calendar data through:
/// `CalendarProvider` (over a `CalendarEventSource`) or
/// `MockCalendarDataProvider`, with no changes to the views either way.
package protocol CalendarDataProviding {
    /// Calendar access right now. False: everything here is empty, and
    /// what's derived from events (HUD, menu bar) stands down.
    var isAuthorized: Bool { get }

    /// The full 6x7 grid of day cells for the month containing `monthAnchor`.
    func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel]

    /// The agenda sections whose date falls within `range` — exactly that
    /// range, nothing more. Pure range-in/sections-out: no notion of "the
    /// current window," "today," or a source's own caching lives in this
    /// contract, so a from-scratch source (e.g. a future SQL-backed
    /// provider) is a drop-in with zero changes to `AgendaSectionStore` or
    /// any view. `async` since answering this may involve real I/O.
    func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection]

    /// Events for exactly one day — for the month grid's hover "glance"
    /// preview, which needs a single arbitrary day's events (possibly
    /// outside the agenda's own pre-fetched window) without pulling the
    /// whole multi-day agenda just to read one day back out of it.
    func events(for date: Date, calendar: Calendar) -> [AgendaEventModel]

    /// Every event matching a search (words anywhere, operator fields, a
    /// date range), in date order — ids and starts only — with the same
    /// calendar visibility and declined rules as everything else here.
    /// Visibility is read on the main actor; the query runs off it.
    @MainActor
    func searchEventMatches(_ query: SearchQueryParts) async -> [SearchMatch]

    /// The best text matches for the palette's top results (bm25, then
    /// closeness to now), with titles, under the same rules.
    @MainActor
    func searchRankedEvents(_ query: SearchQueryParts, limit: Int) async -> [RankedMatch]

    /// Full events for search matches, by id, built off the main thread.
    func searchEvents(ids: [Int64]) async -> [Int64: AgendaEventModel]
}

extension CalendarDataProviding {
    package var isAuthorized: Bool { true }

    @MainActor
    package func searchEventMatches(_ query: SearchQueryParts) async -> [SearchMatch] { [] }
    @MainActor
    package func searchRankedEvents(_ query: SearchQueryParts, limit: Int) async -> [RankedMatch] { [] }
    package func searchEvents(ids: [Int64]) async -> [Int64: AgendaEventModel] { [:] }
}
