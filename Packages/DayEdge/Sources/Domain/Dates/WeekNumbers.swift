import Foundation

/// Week-of-year labels for the month grid, one per row of seven days,
/// following the calendar's own week rules (first weekday and the
/// locale's minimum days in the first week — ISO 8601 for Monday-first
/// grids in most European locales).
package enum WeekNumbers {
    package static func labels(forGridStarting dates: [Date], calendar: Calendar) -> [Int] {
        stride(from: 0, to: dates.count, by: 7).map { index in
            // Sample the middle of the row so year boundaries resolve the
            // way the week itself would.
            let sample = dates[min(index + 3, dates.count - 1)]
            return calendar.component(.weekOfYear, from: sample)
        }
    }
}
