import Foundation
import Domain

/// What the omnibox should show for a resolved `SearchIntent` — a thin
/// presentation mapping, not a second search pipeline. `SearchIntentPipeline`
/// (`Intelligence/SearchIntentPipeline.swift`) stays entirely unaware this
/// type exists; this is purely UI representation of its output.
package struct SearchSuggestion: Equatable {
    package let intent: SearchIntent
    /// SF Symbol name.
    package let systemImageName: String
    package let title: String
    package let isEnabled: Bool
    /// Shown only for a disabled suggestion — e.g. "Event search not
    /// available yet." `nil` for an enabled one.
    package let secondaryText: String?

    package static func make(for intent: SearchIntent, referenceDate: Date, calendar: Calendar) -> SearchSuggestion {
        switch intent {
        case .jumpToDate(let date):
            return SearchSuggestion(
                intent: intent, systemImageName: "calendar",
                title: L10n.tr("searchsuggestion.go.to", "Go to \(String(describing: dayLabel(for: date, referenceDate: referenceDate, calendar: calendar)))"),
                isEnabled: true, secondaryText: nil
            )
        case .jumpToMonth(let date):
            return SearchSuggestion(
                intent: intent, systemImageName: "calendar",
                title: L10n.tr("searchsuggestion.go.to", "Go to \(String(describing: monthLabel(for: date, calendar: calendar)))"),
                isEnabled: true, secondaryText: nil
            )
        case .freeTextSearch(let query):
            // Full-text event search isn't implemented yet — represented
            // honestly (a visible, disabled row) rather than silently
            // doing nothing on Enter, or a fake "no date found" state.
            return SearchSuggestion(
                intent: intent, systemImageName: "magnifyingglass",
                title: L10n.tr("searchsuggestion.search.events.for", "Search events for “\(String(describing: query))”"),
                isEnabled: false, secondaryText: L10n.tr("searchsuggestion.event.search.not.available.yet", "Event search not available yet")
            )
        }
    }

    /// "Today" / "Tomorrow" / "Yesterday", else "Friday 25 Sep" — or
    /// "Friday 25 Sep 2027" if `date`'s year differs from
    /// `referenceDate`'s (the region's order).
    package static func dayLabel(for date: Date, referenceDate: Date, calendar: Calendar) -> String {
        let dates = DatePresentationFormatter.current.with(calendar)
        return dates.relativeDay(date, relativeTo: referenceDate)
            ?? dates.format(date, .compact, relativeTo: referenceDate)
    }

    /// "September 2024".
    private static func monthLabel(for date: Date, calendar: Calendar) -> String {
        DatePresentationFormatter.current.with(calendar).monthYear(date)
    }
}
