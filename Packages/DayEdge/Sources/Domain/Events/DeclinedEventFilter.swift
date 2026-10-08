import Foundation

/// Whether an event should be hidden as "declined by me". Organizer
/// cancellations are deliberately NOT treated as declined: they stay
/// visible so the cleanup/removal flow, which gates on the raw status,
/// keeps working.
package enum DeclinedEventFilter {
    package static func isDeclinedByUser(declinedByMe: Bool, isCanceledByOrganizer: Bool) -> Bool {
        declinedByMe && !isCanceledByOrganizer
    }
}
