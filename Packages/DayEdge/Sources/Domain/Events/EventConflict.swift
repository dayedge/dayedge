import Foundation

/// Is a new event's time free? Read against the events already there —
/// for a repeating event, its first occurrence only.
package enum EventConflict: Equatable, Sendable {
    /// Nothing else at that time.
    case free
    /// Overlaps only events not yet accepted (tentative, no reply).
    case unconfirmed
    /// Overlaps an accepted event — or your own, which needs no reply.
    case busy

    /// All-day events, cancelled and declined ones never block time.
    package static func check(start: Date, end: Date, against events: [AgendaEventModel]) -> EventConflict {
        overlap(start: start, end: end, against: events)?.conflict ?? .free
    }

    /// The event that decides the colour — the earliest accepted one, else
    /// the earliest not accepted; nil when the time is free.
    package static func overlap(start: Date, end: Date, against events: [AgendaEventModel]) -> EventOverlap? {
        let overlapping = events.filter { event in
            guard event.status != .cancelled, event.myResponseStatus != .declined, !event.isAllDay,
                  let otherStart = event.startDate, let otherEnd = event.endDate else { return false }
            return otherStart < end && otherEnd > start
        }
        .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        if let accepted = overlapping.first(where: { $0.myResponseStatus == .accepted || $0.myResponseStatus == nil }) {
            return EventOverlap(conflict: .busy, event: accepted)
        }
        return overlapping.first.map { EventOverlap(conflict: .unconfirmed, event: $0) }
    }
}

/// What a new event's time runs into: the colour and the event shown.
package struct EventOverlap: Equatable {
    package let conflict: EventConflict
    package let event: AgendaEventModel
}
