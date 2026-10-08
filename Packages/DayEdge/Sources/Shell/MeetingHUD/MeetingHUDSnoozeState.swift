import Foundation
import Domain

/// *Why* an occurrence is snoozed, not just *until when* — lets the
/// controller recompute `wakeAt` if the underlying event's start time
/// changes while snoozed (an `.untilMeetingStart` snooze should track a
/// moved start; a `.duration` snooze never should).
enum MeetingHUDSnoozeMode: Equatable {
    case untilMeetingStart
    case duration(TimeInterval)
}

/// Keyed by `MeetingHUDOccurrence.id` in `MeetingHUDController` — already
/// per-occurrence (pairs the event identifier with the occurrence's own
/// start time), so snoozing one recurring instance never affects another.
struct MeetingHUDSnoozeState: Equatable {
    let occurrenceID: String
    let reminderOccurrenceKey: ReminderOccurrenceKey?
    let mode: MeetingHUDSnoozeMode
    let createdAt: Date
    var wakeAt: Date
}
