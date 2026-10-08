import Foundation

package protocol AppleCalendarOpening {
    /// Opens Calendar.app, navigates to, selects, and opens the details
    /// UI for one specific event occurrence. Returns whether the
    /// underlying `NSWorkspace.shared.open` call succeeded.
    @discardableResult
    func openWithDetails(calendarItemIdentifier: String, occurrenceDate: Date) -> Bool
}

package protocol CalendarEventRemoving {
    func removeCancelledOccurrence(_ reference: EventRemovalReference) throws
}

package enum EventRemovalError: Error {
    case occurrenceNotFound
    case noLongerCancelled
    case calendarNotWritable
}

package protocol RecurringOccurrenceFinding: Sendable {
    func adjacent(
        to reference: RecurringSeriesReference,
        direction: OccurrenceDirection
    ) async -> OccurrenceNavigationTarget?
}
