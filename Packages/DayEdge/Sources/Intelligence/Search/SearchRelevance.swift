import Foundation
import Domain

/// How well a result matches, for the palette's top results: the title
/// first — exact, then the query as a phrase, then every word — then
/// matches only in notes, place or people. Within a tier the index's text
/// score (bm25) decides, and closeness to now only breaks ties, so a strong
/// match from two years ago beats a weak one next week.
package enum SearchRelevance {
    package enum Tier: Int, Comparable {
        case exactTitle, titlePhrase, titleWords, elsewhere

        package static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    package static func tier(title: String, query: String) -> Tier {
        let folded = fold(title)
        let phrase = fold(query)
        guard !phrase.isEmpty else { return .elsewhere }
        if folded == phrase { return .exactTitle }
        if folded.contains(phrase) { return .titlePhrase }
        let words = TaskSearch.words(in: query)
        if !words.isEmpty, words.allSatisfy({ folded.contains($0) }) { return .titleWords }
        return .elsewhere
    }

    /// The best `limit` results across events and tasks: strongest tier
    /// first; within a tier, where the Search view starts browsing — the
    /// soonest from today on, then the most recent before — and the text
    /// score (bm25) only on a tie. Tasks follow events at the same place;
    /// undated tasks come last in their tier.
    package static func top(events: [RankedMatch], tasks: [TaskItem], query: String, now: Date, limit: Int,
                            calendar: Calendar = .autoupdatingCurrent) -> [SearchIndex.Entry] {
        struct Scored {
            let entry: SearchIndex.Entry
            let tier: Tier
            /// 0 today or later, 1 before today, 2 undated.
            let when: Int
            /// From the start of today: forward for upcoming, back for past.
            let distance: TimeInterval
            let kind: Int
            /// bm25 (lower is better); 0 for tasks.
            let score: Double
        }
        let today = calendar.startOfDay(for: now)
        func place(_ date: Date?) -> (Int, TimeInterval) {
            guard let date else { return (2, 0) }
            let offset = date.timeIntervalSince(today)
            return offset >= 0 ? (0, offset) : (1, -offset)
        }
        var scored = events.map { ranked in
            let (when, distance) = place(ranked.match.start)
            return Scored(entry: .event(id: ranked.match.id, start: ranked.match.start, isAllDay: ranked.match.isAllDay),
                          tier: tier(title: ranked.title, query: query), when: when, distance: distance, kind: 0, score: ranked.rank)
        }
        scored += tasks.map { task in
            let (when, distance) = place(task.dueDate)
            return Scored(entry: .task(task), tier: tier(title: task.title, query: query), when: when, distance: distance,
                          kind: 1, score: 0)
        }
        scored.sort {
            ($0.tier.rawValue, $0.when, $0.distance, $0.kind, $0.score) < ($1.tier.rawValue, $1.when, $1.distance, $1.kind, $1.score)
        }
        return scored.prefix(limit).map(\.entry)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
