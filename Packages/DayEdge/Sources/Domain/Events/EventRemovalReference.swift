import Foundation

/// Enough to re-locate the *exact* calendar occurrence for removal later
/// — deliberately more than just `eventIdentifier`, since that alone is
/// not enough to disambiguate one instance of a recurring event from
/// another (`EKEventStore.event(withIdentifier:)` is not guaranteed to
/// return the specific occurrence a user clicked — see
/// `EventKitEventRemovalService`, which re-locates the occurrence by
/// identifier *and* start date rather than trusting that lookup alone).
package struct EventRemovalReference: Hashable {
    package let eventIdentifier: String
    package let calendarIdentifier: String
    package let occurrenceStart: Date
    package let occurrenceEnd: Date

    package init(eventIdentifier: String, calendarIdentifier: String, occurrenceStart: Date, occurrenceEnd: Date) {
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.occurrenceStart = occurrenceStart
        self.occurrenceEnd = occurrenceEnd
    }
}
