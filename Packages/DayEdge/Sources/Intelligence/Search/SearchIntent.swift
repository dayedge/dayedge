import Foundation

/// Where the palette's Go to goes: a day or a month.
package enum SearchIntent: Equatable {
    /// Navigate to and select this specific day.
    case jumpToDate(Date)
    /// Show this month without changing which day is selected — the date
    /// is always the first of the target month.
    case jumpToMonth(Date)
}
