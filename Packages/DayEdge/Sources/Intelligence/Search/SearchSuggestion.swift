import Foundation
import Domain

/// The localized title and icon of a navigation or search action.
package struct SearchSuggestion: Equatable {
    package let intent: SearchIntent
    /// SF Symbol name.
    package let systemImageName: String
    package let title: String
    package let isEnabled: Bool
    /// Optional supporting text.
    package let secondaryText: String?

    package static func make(for intent: SearchIntent, referenceDate: Date, calendar: Calendar,
                             dates: DatePresentationFormatter = .current) -> SearchSuggestion {
        switch intent {
        case .jumpToDate(let date):
            return SearchSuggestion(
                intent: intent, systemImageName: "calendar",
                title: L10n.tr("searchsuggestion.go.to", "Go to \(String(describing: dayLabel(for: date, referenceDate: referenceDate, calendar: calendar, dates: dates)))"),
                isEnabled: true, secondaryText: nil
            )
        case .jumpToMonth(let date):
            return SearchSuggestion(
                intent: intent, systemImageName: "calendar",
                title: L10n.tr("searchsuggestion.go.to", "Go to \(String(describing: dates.with(calendar).monthYear(date)))"),
                isEnabled: true, secondaryText: nil
            )
        case .freeTextSearch(let query):
            return SearchSuggestion(
                intent: intent, systemImageName: "magnifyingglass",
                title: L10n.tr("searchsuggestion.search.events.for", "Search events for “\(String(describing: query))”"),
                isEnabled: true, secondaryText: nil
            )
        }
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
