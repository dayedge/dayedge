import Foundation
import Domain

/// How the palette names days: the title of its "Go to …" action, and a day as people say it.
package enum SearchSuggestion {
    /// "Go to Tomorrow", "Go to Friday 25 Sep", "Go to September 2024".
    package static func title(for intent: SearchIntent, referenceDate: Date, calendar: Calendar,
                              dates: DatePresentationFormatter = .current) -> String {
        let target = switch intent {
        case .jumpToDate(let date): dayLabel(for: date, referenceDate: referenceDate, calendar: calendar, dates: dates)
        case .jumpToMonth(let date): dates.with(calendar).monthYear(date)
        }
        return L10n.tr("searchsuggestion.go.to", "Go to \(String(describing: target))")
    }

    /// "Today" / "Tomorrow" / "Yesterday", else "Friday 25 Sep" — or
    /// "Friday 25 Sep 2027" if `date`'s year differs from
    /// `referenceDate`'s (the region's order).
    package static func dayLabel(for date: Date, referenceDate: Date, calendar: Calendar,
                                 dates: DatePresentationFormatter = .current) -> String {
        let dates = dates.with(calendar)
        return dates.relativeDay(date, relativeTo: referenceDate)
            ?? dates.format(date, .compact, relativeTo: referenceDate)
    }
}
