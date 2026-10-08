import EventKit
import Foundation
import Domain

/// Performs bounded, calendar-scoped recurrence lookup away from the main
/// actor. It does not change the agenda cache or retain fetched EKEvents.
package actor EventKitOccurrenceFinder: RecurringOccurrenceFinding {
    private let eventStore: EKEventStore

    package init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    package func adjacent(
        to reference: RecurringSeriesReference,
        direction: OccurrenceDirection
    ) async -> OccurrenceNavigationTarget? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let sourceCalendar = eventStore.calendar(withIdentifier: reference.calendarIdentifier) else { return nil }

        let calendar = Calendar.autoupdatingCurrent
        let yearDelta = direction == .next
            ? AppConfiguration.recurrenceNavigationHorizonYears
            : -AppConfiguration.recurrenceNavigationHorizonYears
        guard let limit = calendar.date(byAdding: .year, value: yearDelta, to: reference.sourceStart) else { return nil }

        var cursor = reference.sourceStart
        while !Task.isCancelled {
            guard let window = RecurringOccurrenceResolver.nextSearchWindow(
                from: cursor, limit: limit, direction: direction, calendar: calendar
            ) else { return nil }
            let predicate = eventStore.predicateForEvents(
                withStart: window.start, end: window.end, calendars: [sourceCalendar]
            )
            let candidates = eventStore.events(matching: predicate).compactMap(Self.candidate)
            if let target = RecurringOccurrenceResolver.closest(
                to: reference, direction: direction, among: candidates
            ) {
                return Task.isCancelled ? nil : target
            }
            cursor = direction == .next ? window.end : window.start
            if cursor == limit { return nil }
        }
        return nil
    }

    private static func candidate(from event: EKEvent) -> RecurringOccurrenceCandidate? {
        guard let seriesIdentifier = event.calendarItemExternalIdentifier,
              let eventIdentifier = event.eventIdentifier,
              !seriesIdentifier.isEmpty,
              !eventIdentifier.isEmpty,
              let startDate = event.startDate else { return nil }
        let declined = event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
        return RecurringOccurrenceCandidate(
            seriesIdentifier: CalendarEventMapper.seriesIdentifier(seriesIdentifier),
            calendarIdentifier: event.calendar.calendarIdentifier,
            eventID: CalendarEventMapper.eventID(for: event),
            startDate: startDate,
            occurrenceDate: event.occurrenceDate,
            isRelevant: event.status != .canceled && !declined
        )
    }
}
