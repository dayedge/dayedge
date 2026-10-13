import Foundation
import Domain
import TimeWhisper

/// Adapts library ranges to navigation and day-based search; never reads text.
package enum TemporalPresentation {
    package static func navigation(_ found: FoundTemporal, calendar: Calendar) -> SearchIntent? {
        guard found.remainingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch found.temporal.granularity {
        case .month, .year: return .jumpToMonth(found.temporal.start.date)
        case .day, .week: return .jumpToDate(calendar.startOfDay(for: found.temporal.start.date))
        }
    }

    package static func interval(_ temporal: TemporalSpec, calendar: Calendar) -> DateInterval {
        let start = temporal.start.date
        let end = temporal.endExclusive.date
        guard temporal.hasExplicitTime || end == start else { return DateInterval(start: start, end: end) }
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        let exclusive = end > start && end == last ? end : (calendar.dateInterval(of: .day, for: end)?.end ?? end)
        return DateInterval(start: first, end: exclusive)
    }

    package static func searchParts(_ query: String, found: FoundTemporal?, calendar: Calendar,
                                    dates: DatePresentationFormatter = .current) -> SearchQueryParts {
        guard let found else { return .plain(query) }
        let range = interval(found.temporal, calendar: calendar)
        let dates = dates.with(calendar)
        let label: String
        switch found.temporal.granularity {
        case .month: label = dates.monthYear(range.start)
        case .year: label = dates.year(range.start)
        case .day, .week:
            label = dates.format(range.start, .compact, weekday: .abbreviated, year: .outsideCurrentYear)
        }
        return SearchQueryParts(text: found.remainingText, interval: range, label: label)
    }
}
