import Foundation

package enum OccurrenceDirection: Sendable {
    case previous
    case next
}

/// Identifies the series and the occurrence from which a menu jump starts.
/// The external identifier is shared by a recurring series; the calendar
/// identifier keeps duplicate subscriptions or invitations separate.
package struct RecurringSeriesReference: Hashable, Sendable {
    package let seriesIdentifier: String
    package let calendarIdentifier: String
    package let sourceEventID: String
    package let sourceStart: Date
    package let sourceOccurrenceDate: Date?

    package init(seriesIdentifier: String, calendarIdentifier: String, sourceEventID: String, sourceStart: Date, sourceOccurrenceDate: Date?) {
        self.seriesIdentifier = seriesIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.sourceEventID = sourceEventID
        self.sourceStart = sourceStart
        self.sourceOccurrenceDate = sourceOccurrenceDate
    }
}

/// Plain values crossing from EventKit lookup back to UI navigation.
package struct OccurrenceNavigationTarget: Equatable, Sendable {
    package let eventID: String
    package let startDate: Date

    package init(eventID: String, startDate: Date) {
        self.eventID = eventID
        self.startDate = startDate
    }
}

/// A lightweight projection of an EventKit result. No EKEvent escapes the
/// background lookup, and filtering/ordering can be tested without EventKit.
package struct RecurringOccurrenceCandidate: Sendable {
    package let seriesIdentifier: String
    package let calendarIdentifier: String
    package let eventID: String
    package let startDate: Date
    package let occurrenceDate: Date?
    package let isRelevant: Bool

    package init(seriesIdentifier: String, calendarIdentifier: String, eventID: String, startDate: Date, occurrenceDate: Date?, isRelevant: Bool) {
        self.seriesIdentifier = seriesIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.eventID = eventID
        self.startDate = startDate
        self.occurrenceDate = occurrenceDate
        self.isRelevant = isRelevant
    }
}

package enum RecurringOccurrenceResolver {
    /// Bounded, contiguous windows keep each EventKit query small while
    /// permitting a sparse series to be searched up to the caller's limit.
    package static func nextSearchWindow(
        from cursor: Date, limit: Date, direction: OccurrenceDirection,
        calendar: Calendar, chunkMonths: Int = 3
    ) -> DateInterval? {
        guard chunkMonths > 0 else { return nil }
        let monthDelta = direction == .next ? chunkMonths : -chunkMonths
        guard let next = calendar.date(byAdding: .month, value: monthDelta, to: cursor) else { return nil }
        let edge = direction == .next ? min(next, limit) : max(next, limit)
        guard direction == .next ? edge > cursor : edge < cursor else { return nil }
        return DateInterval(start: min(cursor, edge), end: max(cursor, edge))
    }

    package static func closest(
        to reference: RecurringSeriesReference,
        direction: OccurrenceDirection,
        among candidates: [RecurringOccurrenceCandidate]
    ) -> OccurrenceNavigationTarget? {
        let matches = candidates.filter { candidate in
            guard candidate.seriesIdentifier == reference.seriesIdentifier,
                  candidate.calendarIdentifier == reference.calendarIdentifier,
                  candidate.isRelevant,
                  candidate.eventID != reference.sourceEventID else { return false }
            if let sourceDate = reference.sourceOccurrenceDate,
               candidate.occurrenceDate == sourceDate { return false }
            switch direction {
            case .previous: return candidate.startDate < reference.sourceStart
            case .next: return candidate.startDate > reference.sourceStart
            }
        }
        let nearest: RecurringOccurrenceCandidate?
        switch direction {
        case .previous: nearest = matches.max { $0.startDate < $1.startDate }
        case .next: nearest = matches.min { $0.startDate < $1.startDate }
        }
        return nearest.map {
            OccurrenceNavigationTarget(eventID: $0.eventID, startDate: $0.startDate)
        }
    }
}
