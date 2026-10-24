import Foundation

/// Turns a tool's `when` argument into days. The model passes ISO days it copied from the dates in its instructions
/// (`AssistantInstructions.dates`), never phrases: a tool argument is read exactly, the same way every time, and every answer echoes
/// the absolute dates back, so the model is grounded in what it got.
package enum AssistantWhen {
    /// For parameter descriptions: what `when` accepts.
    package static let accepted = "a day as 2026-10-02, or days as 2026-10-01..2026-10-07 (both included)"
    /// What `when` accepts where a period may be open (searching).
    package static let acceptedOpen = accepted + "; leave one side open for 'from' or 'until': 2026-10-01.. or ..2026-10-07"

    package struct Unrecognized: Error, Equatable {
        package let text: String
        /// What the argument should have looked like, for the message back to the model.
        package var expected = AssistantWhen.accepted
    }

    /// `text`'s days, or, when it is left out, `defaultDays` from today (1 is today).
    package static func resolve(_ text: String?, defaultDays: Int, allowsOpenEnds: Bool = false,
                                context: AssistantToolContext) throws -> DateInterval {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            let calendar = context.calendar
            let today = calendar.startOfDay(for: context.now())
            return DateInterval(start: today, end: calendar.date(byAdding: .day, value: defaultDays, to: today) ?? today)
        }
        return try resolve(text, allowsOpenEnds: allowsOpenEnds, context: context)
    }

    /// "2026-10-02" or "2026-10-01..2026-10-07"; with `allowsOpenEnds`, also "2026-10-01.." (from that day on) and
    /// "..2026-10-07" (until it, included). Only a search takes an open period: the other tools go day by day.
    package static func resolve(_ text: String, allowsOpenEnds: Bool = false, context: AssistantToolContext) throws -> DateInterval {
        let calendar = context.calendar
        let ends = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "..")
        let unrecognized = Unrecognized(text: text, expected: allowsOpenEnds ? acceptedOpen : accepted)
        func day(_ part: String) throws -> Date {
            guard let day = AssistantDateText.day(part, calendar) else { throw unrecognized }
            return day
        }
        func dayAfter(_ day: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        switch ends.count {
        case 1:
            let only = try day(ends[0])
            return DateInterval(start: only, end: dayAfter(only))
        case 2 where allowsOpenEnds && ends[0].isEmpty && !ends[1].isEmpty:
            return DateInterval(start: .distantPast, end: dayAfter(try day(ends[1])))
        case 2 where allowsOpenEnds && !ends[0].isEmpty && ends[1].isEmpty:
            return DateInterval(start: try day(ends[0]), end: .distantFuture)
        case 2:
            let start = try day(ends[0]), end = dayAfter(try day(ends[1]))
            guard start < end else { throw unrecognized }
            return DateInterval(start: start, end: end)
        default:
            throw unrecognized
        }
    }

    /// The days an interval covers, at most `limit`.
    package static func days(in interval: DateInterval, calendar: Calendar, limit: Int) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end, days.count < limit {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }
}

/// The forms tool arguments take, read exactly and never guessed: a day "2026-10-02", a 24-hour time "15:00".
package enum AssistantDateText {
    /// The start of the day "2026-10-02" in the calendar's zone; nil for anything else, an impossible day included.
    package static func day(_ text: String, _ calendar: Calendar) -> Date? {
        guard let match = text.trimmingCharacters(in: .whitespaces).wholeMatch(of: #/(\d{4})-(\d{2})-(\d{2})/#),
              let year = Int(match.1), let month = Int(match.2), let day = Int(match.3) else { return nil }
        let parts = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: parts), calendar.dateComponents([.year, .month, .day], from: date) == parts else { return nil }
        return date
    }

    /// "15:00", "9:30" or "15:00:00" as hour and minute; nil for anything else.
    package static func time(_ text: String) -> (hour: Int, minute: Int)? {
        guard let match = text.trimmingCharacters(in: .whitespaces).wholeMatch(of: #/(\d{1,2}):(\d{2})(?::00)?/#),
              let hour = Int(match.1), let minute = Int(match.2), (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }
}
