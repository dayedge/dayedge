import EventKit
import Foundation
import Domain

/// The one place the app performs a destructive EventKit write. Split
/// out from `EventActionCoordinator` (which owns alerts/`NSWorkspace`/
/// pasteboard side effects) so this narrow, careful lookup-and-validate
/// logic has its own seam (`CalendarEventRemoving`) a fake can stand in
/// for elsewhere, independent of needing a live `EKEventStore`.
package final class EventKitEventRemovalService: CalendarEventRemoving {
    private let eventStore: EKEventStore

    package init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    package func removeCancelledOccurrence(_ reference: EventRemovalReference) throws {
        // A bounded fetch matched on identifier *and* the occurrence's own
        // start date — not `event(withIdentifier:)` alone, which is not
        // guaranteed to resolve to this specific instance of a recurring
        // event (it can return a different occurrence sharing the same
        // identifier). A tight ±60s window around the known occurrence
        // times keeps the fetch cheap while tolerant of any rounding.
        let searchStart = reference.occurrenceStart.addingTimeInterval(-60)
        let searchEnd = reference.occurrenceEnd.addingTimeInterval(60)
        let calendars = eventStore.calendar(withIdentifier: reference.calendarIdentifier).map { [$0] }
        let predicate = eventStore.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: calendars)

        guard let match = eventStore.events(matching: predicate).first(where: {
            $0.eventIdentifier == reference.eventIdentifier &&
            $0.calendar.calendarIdentifier == reference.calendarIdentifier &&
            $0.startDate == reference.occurrenceStart
        }) else {
            throw EventRemovalError.occurrenceNotFound
        }

        // Revalidate at the moment of deletion — state may have changed
        // between the right-click and confirming the alert.
        guard match.status == .canceled else { throw EventRemovalError.noLongerCancelled }
        guard match.calendar.allowsContentModifications else { throw EventRemovalError.calendarNotWritable }

        try eventStore.remove(match, span: .thisEvent, commit: true)
        EventKitEventEditor.announceWrite(.write(before: (reference.calendarIdentifier, reference.occurrenceStart,
                                                          reference.occurrenceEnd), after: nil, throughFuture: false))
    }
}
