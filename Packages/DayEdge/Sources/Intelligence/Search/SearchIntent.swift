import Foundation

/// What the search bar's text should actually do — resolved by
/// `SearchIntentPipeline`, an ordered list of pluggable stages.
package enum SearchIntent: Equatable {
    /// Navigate to and select this specific day.
    case jumpToDate(Date)
    /// Show this month without changing which day is selected — the date
    /// is always the first of the target month.
    case jumpToMonth(Date)
    /// Full-text event search — not implemented yet (see project notes);
    /// resolved and passed through so the UI has somewhere to route it
    /// once that lands.
    case freeTextSearch(String)
}
