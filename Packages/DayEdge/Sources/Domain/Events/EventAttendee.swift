import Foundation

/// One attendee on an event, for the event-detail popover's attendee list.
package struct EventAttendee: Identifiable, Hashable {
    /// Who this is — email, else name — so the same person keeps the same
    /// id across reloads and SwiftUI updates their row instead of
    /// recreating the whole list. `CalendarEventMapper` suffixes repeats.
    package let id: String
    package let name: String
    package let status: Status
    /// EventKit exposes no direct "email" field on a participant — this is
    /// pulled from `EKParticipant.url` when it's a `mailto:` URL (see
    /// `CalendarEventMapper`), which is nil for a
    /// participant EventKit only knows a display name for. Callers that
    /// want "the best copyable identifier" for an attendee should fall
    /// back to `name` when this is nil.
    package var email: String?
    /// This attendee is the user (EventKit's `isCurrentUser`).
    package var isCurrentUser = false

    package init(name: String, status: Status, email: String? = nil, isCurrentUser: Bool = false, id: String? = nil) {
        self.id = id ?? Self.identity(name: name, email: email)
        self.name = name
        self.status = status
        self.email = email
        self.isCurrentUser = isCurrentUser
    }

    package static func identity(name: String, email: String?) -> String {
        if let email, !email.isEmpty { return "mail:" + email.lowercased() }
        return "name:" + name
    }

    /// The same list with every id unique: a repeated person (two "Unknown"
    /// attendees without an address) gets "#2", "#3"… in list order.
    package static func uniquingIDs(_ attendees: [EventAttendee]) -> [EventAttendee] {
        var seen: [String: Int] = [:]
        return attendees.map { attendee in
            let count = (seen[attendee.id] ?? 0) + 1
            seen[attendee.id] = count
            guard count > 1 else { return attendee }
            return EventAttendee(name: attendee.name, status: attendee.status, email: attendee.email,
                                 isCurrentUser: attendee.isCurrentUser, id: "\(attendee.id)#\(count)")
        }
    }

    package enum Status: Hashable {
        case accepted
        case declined
        case tentative
        case pending
        case unknown
    }
}
