import Foundation

/// One event matching a search, without its payload: enough to place it on
/// a day; the full event is loaded by `id` when shown.
package struct SearchMatch: Sendable, Hashable {
    package var id: Int64
    package var start: Date
    package var isAllDay: Bool

    package init(id: Int64, start: Date, isAllDay: Bool) {
        self.id = id
        self.start = start
        self.isAllDay = isAllDay
    }
}

/// A match with its title and text score (bm25 — lower is better), for
/// ranking without loading the event.
package struct RankedMatch: Sendable, Hashable {
    package var match: SearchMatch
    package var title: String
    package var rank: Double

    package init(match: SearchMatch, title: String, rank: Double) {
        self.match = match
        self.title = title
        self.rank = rank
    }
}
