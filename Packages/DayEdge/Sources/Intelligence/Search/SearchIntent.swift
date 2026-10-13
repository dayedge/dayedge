import Foundation

/// The navigation or search action selected in the palette.
package enum SearchIntent: Equatable {
    /// Navigate to and select this specific day.
    case jumpToDate(Date)
    /// Show this month without changing which day is selected — the date
    /// is always the first of the target month.
    case jumpToMonth(Date)
    /// Search events and tasks with the original query.
    case freeTextSearch(String)
}
