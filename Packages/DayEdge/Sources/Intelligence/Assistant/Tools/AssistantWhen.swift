import Foundation

/// Turns a tool's `when` argument into days. Dates are resolved here, by
/// the app's own parsers — never computed by the model — and every answer
/// echoes the absolute dates back, so the model is grounded in what it got.
package enum AssistantWhen {
    /// For parameter descriptions: what `when` accepts.
    package static let accepted = "today, tomorrow, this week, next week, next 7 days, this month, "
        + "a date (2026-10-02), a range (2026-10-01..2026-10-07) or a phrase like 'next friday'"

    package struct Unrecognized: Error, Equatable {
        package let text: String
    }

    /// Keywords, ISO dates and ranges first (exact); anything else goes to
    /// the search field's date parser (`parse`), which knows single days
    /// and months.
    package static func resolve(_ text: String, context: AssistantToolContext) async throws -> DateInterval {
        let now = context.now()
        if let interval = exact(text, now: now, calendar: context.calendar) { return interval }
        let calendar = context.calendar
        switch await context.parseDate(text, now, calendar) {
        case .jumpToDate(let date):
            return day(date, calendar: calendar)
        case .jumpToMonth(let date):
            return calendar.dateInterval(of: .month, for: date) ?? day(date, calendar: calendar)
        case .freeTextSearch:
            throw Unrecognized(text: text)
        }
    }

    // swiftlint:disable cyclomatic_complexity - one case per accepted when-phrase
    /// The part that needs no parser — pure, for tests.
    package static func exact(_ text: String, now: Date, calendar: Calendar) -> DateInterval? {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let today = calendar.startOfDay(for: now)
        func shifted(_ component: Calendar.Component, _ value: Int) -> Date {
            calendar.date(byAdding: component, value: value, to: today) ?? today
        }
        switch phrase {
        case "", "today": return day(today, calendar: calendar)
        case "tomorrow": return day(shifted(.day, 1), calendar: calendar)
        case "yesterday": return day(shifted(.day, -1), calendar: calendar)
        case "this week": return calendar.dateInterval(of: .weekOfYear, for: today)
        case "next week": return calendar.dateInterval(of: .weekOfYear, for: shifted(.weekOfYear, 1))
        case "last week": return calendar.dateInterval(of: .weekOfYear, for: shifted(.weekOfYear, -1))
        case "this month": return calendar.dateInterval(of: .month, for: today)
        case "next month": return calendar.dateInterval(of: .month, for: shifted(.month, 1))
        default: break
        }
        if let days = nextDays(phrase), days > 0 {
            return DateInterval(start: today, end: shifted(.day, days))
        }
        let bounds = phrase.components(separatedBy: "..").map { $0.trimmingCharacters(in: .whitespaces) }
        if bounds.count == 2, let first = isoDay(bounds[0], calendar: calendar), let last = isoDay(bounds[1], calendar: calendar), first <= last {
            return DateInterval(start: first, end: calendar.date(byAdding: .day, value: 1, to: last) ?? last)
        }
        if let date = isoDay(phrase, calendar: calendar) { return day(date, calendar: calendar) }
        return nil
    }
    // swiftlint:enable cyclomatic_complexity

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

    private static func day(_ date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    /// "next 7 days", "next 3 day".
    private static func nextDays(_ phrase: String) -> Int? {
        let words = phrase.split(separator: " ")
        guard words.count == 3, words[0] == "next", words[2].hasPrefix("day") else { return nil }
        return Int(words[1])
    }

    private static func isoDay(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, text.count == 10 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
