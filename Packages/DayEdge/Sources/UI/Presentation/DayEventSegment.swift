import Foundation
import Domain

/// A timed event's relationship to one displayed calendar day — the same
/// event renders differently depending on whether the day is looking at
/// its start, its end, the whole of it in between, or the ordinary
/// same-day case. Deliberately not a new model: every agenda row / day-
/// timeline block derives this on the fly from the one shared
/// `AgendaEventModel` plus the day it happens to be rendered on, rather
/// than the app carrying one duplicated event per day it spans.
package enum DayEventSegment: Equatable {
    case sameDay
    case startsHereEndsLater
    case continuesThroughDay
    case endsHere
}

package enum MultiDaySegment {
    /// `nil` means the event doesn't occupy `day` at all (or `start`/`end`
    /// don't form a valid, positive-duration span).
    package static func classify(start: Date, end: Date, day: Date, calendar: Calendar) -> DayEventSegment? {
        guard start < end else { return nil }
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        guard start < dayEnd, end > dayStart else { return nil }

        let startDay = calendar.startOfDay(for: start)
        // An event ending exactly on a midnight boundary is exclusive of
        // that following day — "Tue 15:00 → Wed 00:00" occupies only
        // Tuesday, not an empty sliver of Wednesday.
        let endBoundary = calendar.startOfDay(for: end)
        let endDay = end == endBoundary
            ? calendar.date(byAdding: .day, value: -1, to: endBoundary) ?? endBoundary
            : endBoundary

        switch (startDay == dayStart, endDay == dayStart) {
        case (true, true): return .sameDay
        case (true, false): return .startsHereEndsLater
        case (false, true): return .endsHere
        default: return .continuesThroughDay
        }
    }

    /// True when a `.sameDay` segment's `end` actually lands exactly on
    /// the following midnight boundary — `classify` treats that as still
    /// "this day" (the following day would have zero duration), but the
    /// label still needs to say "…– Midnight" rather than a plain end
    /// time, since the two real calendar days differ.
    package static func endsAtMidnightBoundary(start: Date, end: Date, calendar: Calendar) -> Bool {
        !calendar.isDate(start, inSameDayAs: end)
    }
}
