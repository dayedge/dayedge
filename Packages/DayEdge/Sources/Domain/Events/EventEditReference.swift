import Foundation

/// How the app finds one event occurrence again to change it — and
/// whether it may. Set by the mapper for every EventKit event; the editor
/// revalidates both facts at the moment of writing.
package struct EventEditReference: Hashable, Sendable {
    package let eventIdentifier: String
    package let calendarIdentifier: String
    package let occurrenceStart: Date
    package let occurrenceEnd: Date
    /// The calendar allows changes.
    package let isWritable: Bool
    /// Someone else's invitation (it has attendees and the user isn't the
    /// organizer): the app never edits or deletes those. The organizer's
    /// name, when known.
    package let invitationFrom: String?
    package let isInvitation: Bool
    /// Other people are invited (whoever organizes it).
    package var hasAttendees = false

    package init(
        eventIdentifier: String,
        calendarIdentifier: String,
        occurrenceStart: Date,
        occurrenceEnd: Date,
        isWritable: Bool,
        invitationFrom: String?,
        isInvitation: Bool,
        hasAttendees: Bool = false
    ) {
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.occurrenceStart = occurrenceStart
        self.occurrenceEnd = occurrenceEnd
        self.isWritable = isWritable
        self.invitationFrom = invitationFrom
        self.isInvitation = isInvitation
        self.hasAttendees = hasAttendees
    }
}
