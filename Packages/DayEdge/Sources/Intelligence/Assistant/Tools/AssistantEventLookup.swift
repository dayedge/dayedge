import Foundation
import Domain

/// Sequential bounded reads of a complete requested range. The consumer keeps
/// only the candidates it needs; each chunk's full models die before the next.
package enum AssistantEventLookup {
    package static let chunkDays = 31

    private struct UnrepresentableRange: Error {}

    package static func scan(in range: DateInterval, context: AssistantToolContext,
                             consume: (AgendaDaySection) -> Void) async throws {
        let calendar = context.calendar
        var cursor = calendar.startOfDay(for: range.start)
        while cursor < range.end {
            try Task.checkCancellation()
            guard let following = calendar.date(byAdding: .day, value: chunkDays, to: cursor), following > cursor else {
                throw UnrepresentableRange()
            }
            let end = min(following, range.end)
            // The app's day-based provider hydrates its end calendar day
            // inclusively. A midnight boundary must fetch only through the
            // preceding day, while scanning still advances to logical `end`.
            let fetchEnd = end == calendar.startOfDay(for: end) ? end.addingTimeInterval(-1) : end
            let sections = await context.data.agenda(in: DateInterval(start: cursor, end: fetchEnd), calendar: calendar)
            try Task.checkCancellation()
            // Calendar providers may include the end day. It belongs only to
            // the following chunk, never to both or outside the requested range.
            for section in sections.filter({ $0.date >= cursor && $0.date < end }).sorted(by: { $0.date < $1.date }) {
                consume(section)
            }
            cursor = end
        }
        try Task.checkCancellation()
    }

    /// One referenced occurrence, read from its own day only.
    package static func event(id: String, on day: Date, context: AssistantToolContext) async throws -> AgendaEventModel? {
        let calendar = context.calendar
        let interval = DateInterval(start: day, end: calendar.date(byAdding: .day, value: 1, to: day) ?? day)
        let events = await context.data.agenda(in: interval, calendar: calendar).flatMap(\.events)
        try Task.checkCancellation()
        return events.first { $0.id == id }
    }
}

/// A prefix of candidates and its full count: a truncated preview must never
/// turn an ambiguous change target into a unique one.
package struct AssistantCandidates<Item> {
    package private(set) var items: [Item] = []
    package private(set) var count = 0
    package static var previewLimit: Int { 8 }

    package mutating func append(_ item: Item) {
        count += 1
        if items.count < Self.previewLimit { items.append(item) }
    }
}
