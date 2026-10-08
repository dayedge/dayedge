import Foundation
import Domain

package enum SearchQueryResolver {
    // swiftlint:disable cyclomatic_complexity function_body_length - one branch per search operator
    /// Operators out first; date values through the app's date parsing
    /// (ISO `yyyy-MM-dd`, else chrono). A date phrase in the free words
    /// still narrows ("standup tomorrow") unless an operator set a date.
    package static func resolve(_ query: String, referenceDate: Date, calendar: Calendar) async -> SearchQueryParts {
        let parsed = SearchQuerySyntax.parse(query)
        var parts = SearchQueryParts(text: parsed.freeText)
        var labels: [String] = []
        let values = parsed.values

        parts.subject = values[.subject]
        if let organizer = values[.from] {
            if organizer.lowercased() == "me" {
                parts.organizedByMe = true
            } else {
                parts.organizer = organizer
            }
            labels.append(parts.organizedByMe ? "from me" : "from \(organizer)")
        }
        if let attendee = values[.with] {
            parts.attendee = attendee
            labels.append("with \(attendee)")
        }
        if let type = values[.type] {
            parts.kind = kind(type)
            if let kind = parts.kind { labels.append(kind == .event ? "Events" : "Tasks") }
        }

        var intervals: [DateInterval] = []
        func day(_ value: String) async -> (DateInterval, String)? {
            await dayInterval(value, referenceDate: referenceDate, calendar: calendar)
        }
        if let value = values[.day], let (interval, label) = await day(value) {
            intervals.append(interval)
            labels.append(label)
        }
        if let value = values[.after], let (interval, label) = await day(value) {
            intervals.append(DateInterval(start: interval.start, end: .distantFuture))
            labels.append("after \(label)")
        }
        if let value = values[.before], let (interval, label) = await day(value) {
            intervals.append(DateInterval(start: .distantPast, end: interval.start))
            labels.append("before \(label)")
        }
        if let value = values[.between] {
            let ends = value.components(separatedBy: "..")
            if ends.count == 2, let (from, fromLabel) = await day(ends[0]), let (to, toLabel) = await day(ends[1]),
               from.start < to.end {
                intervals.append(DateInterval(start: from.start, end: to.end))
                labels.append("\(fromLabel) – \(toLabel)")
            }
        }
        if !intervals.isEmpty {
            parts.hasExplicitDate = true
            // All of them at once; ranges that don't overlap match nothing.
            parts.interval = intervals.dropFirst().reduce(intervals[0]) { result, next in
                result.intersection(with: next) ?? DateInterval(start: .distantPast, duration: 0)
            }
        } else if !parts.text.isEmpty {
            let phrase = await SearchDateFilter.parse(parts.text, referenceDate: referenceDate, calendar: calendar)
            parts.text = phrase.text
            parts.interval = phrase.interval
            if let label = phrase.label { labels.append(label) }
        }
        parts.label = labels.isEmpty ? nil : labels.joined(separator: " · ")
        return parts
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    package static func kind(_ value: String) -> SearchQueryParts.Kind? {
        switch value.lowercased() {
        case "event", "events", "e": .event
        case "task", "tasks", "t": .task
        default: nil
        }
    }

    /// A day (or a month) a value names, with how to say it.
    package static func dayInterval(_ value: String, referenceDate: Date, calendar: Calendar) async -> (DateInterval, String)? {
        let value = value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if let day = isoDay(value, calendar: calendar), let interval = calendar.dateInterval(of: .day, for: day) {
            let dates = DatePresentationFormatter.current.with(calendar)
            return (interval, dates.format(day, .compact, weekday: .abbreviated, relativeTo: referenceDate))
        }
        // The whole value must be the date phrase ("next friday").
        let phrase = await SearchDateFilter.parse(value, referenceDate: referenceDate, calendar: calendar)
        guard phrase.text.isEmpty, let interval = phrase.interval else { return nil }
        return (interval, phrase.label ?? value)
    }

    private static func isoDay(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        // Reject rollovers (2026-02-31).
        return date.flatMap { calendar.component(.day, from: $0) == day ? $0 : nil }
    }
}
