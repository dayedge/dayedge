import Foundation
import Domain

package enum SearchQueryResolver {
    // swiftlint:disable cyclomatic_complexity function_body_length - one branch per search operator
    /// Operators out first; date values through the app's date parsing
    /// (TimeWhisper). A date phrase in the free words
    /// still narrows ("standup tomorrow") unless an operator set a date.
    package static func resolve(_ query: String, referenceDate: Date, calendar: Calendar) async -> SearchQueryParts {
        let parsed = SearchQuerySyntax.parse(query)
        let values = parsed.values
        var (parts, labels) = words(parsed.freeText, values: values)
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
            let found = await NaturalLanguageParser.live.findTemporal(parts.text, referenceDate: referenceDate, calendar: calendar)
            let phrase = TemporalPresentation.searchParts(parts.text, found: found, calendar: calendar)
            parts.text = phrase.text
            parts.interval = phrase.interval
            if let label = phrase.label { labels.append(label) }
        }
        parts.label = labels.isEmpty ? nil : labels.joined(separator: " · ")
        return parts
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    /// The free words and the operators that are not dates (subject, from — "me" too —, with, type), with how each
    /// reads in the label. The assistant's search takes these as they are and its dates separately.
    package static func words(_ text: String, values: [SearchOperator: String]) -> (parts: SearchQueryParts, labels: [String]) {
        var parts = SearchQueryParts(text: text)
        var labels: [String] = []
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
        return (parts, labels)
    }

    package static func kind(_ value: String) -> SearchQueryParts.Kind? {
        switch value.lowercased() {
        case "event", "events", "e": .event
        case "task", "tasks", "t": .task
        default: nil
        }
    }

    /// The days an operator's value names, read whole ("friday", "next month"), with how to say them.
    package static func dayInterval(_ value: String, referenceDate: Date, calendar: Calendar) async -> (DateInterval, String)? {
        let value = value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty,
              let temporal = await NaturalLanguageParser.live.parseTemporal(value, referenceDate: referenceDate, calendar: calendar)
        else { return nil }
        let interval = TemporalPresentation.interval(temporal, calendar: calendar)
        return (interval, TemporalPresentation.label(temporal, interval: interval, calendar: calendar))
    }
}
