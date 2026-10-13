import Foundation

/// Turns a tool's `when` argument into days. Dates are resolved here, by
/// TimeWhisper — never computed by the model — and every answer
/// echoes the absolute dates back, so the model is grounded in what it got.
package enum AssistantWhen {
    /// For parameter descriptions: what `when` accepts.
    package static let accepted = "today, tomorrow, this week, next week, next 7 days, this month, "
        + "a date (2026-10-02), a range (2026-10-01..2026-10-07) or a phrase like 'next friday'"

    package struct Unrecognized: Error, Equatable {
        package let text: String
    }

    package static func resolve(_ text: String, context: AssistantToolContext) async throws -> DateInterval {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let interval = await context.resolveTemporal(query.isEmpty ? "today" : query, context.now(), context.calendar) else {
            throw Unrecognized(text: text)
        }
        return interval
    }

    /// The days an interval covers, at most `limit`.
    package static func days(in interval: DateInterval, calendar: Calendar, limit: Int) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end, days.count < limit {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

}
