import Foundation
import Domain

/// Adapts library ranges to navigation and day-based search; never reads text.
package enum TemporalPresentation {
    package static func navigation(_ found: FoundDate, calendar: Calendar) -> SearchIntent? {
        guard found.remainingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch found.date.span {
        case .month, .year: return .jumpToMonth(found.date.start)
        case .day, .week: return .jumpToDate(calendar.startOfDay(for: found.date.start))
        }
    }

    package static func interval(_ date: ParsedDate, calendar: Calendar) -> DateInterval {
        let start = date.start
        let end = date.end
        guard date.hasTime || end == start else { return DateInterval(start: start, end: end) }
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        let exclusive = end > start && end == last ? end : (calendar.dateInterval(of: .day, for: end)?.end ?? end)
        return DateInterval(start: first, end: exclusive)
    }

    package static func searchParts(_ query: String, found: FoundDate?, calendar: Calendar) -> SearchQueryParts {
        guard let found else { return .plain(query) }
        let range = interval(found.date, calendar: calendar)
        return SearchQueryParts(text: found.remainingText, interval: range, label: label(found.date, interval: range, calendar: calendar))
    }

    /// How to name the days a search covers: "Oct 2026", "2026", or the first day ("Fri 2 Oct").
    package static func label(_ date: ParsedDate, interval: DateInterval, calendar: Calendar) -> String {
        let dates = DatePresentationFormatter.current.with(calendar)
        return switch date.span {
        case .month: dates.monthYear(interval.start)
        case .year: dates.year(interval.start)
        case .day, .week: dates.format(interval.start, .compact, weekday: .abbreviated, year: .outsideCurrentYear)
        }
    }
}
