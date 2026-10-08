import Foundation

/// Free gaps between busy times inside a day's working window. Pure: the
/// assistant's `find_free_time` feeds it events; nothing here reads data.
package enum FreeTimeFinder {
    package static let workdayStartHour = 9
    package static let workdayEndHour = 17

    /// The part of `day` worth offering: working hours, and for today only
    /// what's still ahead. nil when nothing is left.
    package static func workingWindow(on day: Date, now: Date, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.date(bySettingHour: workdayStartHour, minute: 0, second: 0, of: day),
              let end = calendar.date(bySettingHour: workdayEndHour, minute: 0, second: 0, of: day) else { return nil }
        let from = max(start, now)
        return from < end ? DateInterval(start: from, end: end) : nil
    }

    /// What blocks time: timed, not cancelled or declined. All-day events
    /// (holidays, birthdays, OOO markers) don't.
    package static func busyIntervals(_ events: [AgendaEventModel]) -> [DateInterval] {
        events.compactMap { event in
            guard !event.isAllDay, event.status != .cancelled,
                  let start = event.startDate, let end = event.endDate, end > start else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    /// Gaps of at least `minimum` in `window` not covered by `busy`
    /// (which may overlap and be in any order).
    package static func gaps(in window: DateInterval, busy: [DateInterval], minimum: TimeInterval) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var cursor = window.start
        for interval in busy.sorted(by: { $0.start < $1.start }) where interval.end > cursor && interval.start < window.end {
            if interval.start > cursor, interval.start.timeIntervalSince(cursor) >= minimum {
                gaps.append(DateInterval(start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if window.end > cursor, window.end.timeIntervalSince(cursor) >= minimum {
            gaps.append(DateInterval(start: cursor, end: window.end))
        }
        return gaps
    }
}
