import Foundation
import Domain

// Quick Add turns a sentence into a task draft by *extraction*, not NLP:
// independent extractors find recognized pieces anywhere in the text ("10
// am", "next week", "#work", "!!"), those pieces are removed, and what is
// left becomes the title. Every range refers to the same normalized text,
// which is never rewritten while parsing.

/// Where a recognized piece came from. A future AI parser produces the
/// same model with `.futureAI`.
package enum ParseSource: String, Sendable {
    case explicitSyntax
    case builtInGrammar
    case chrono
    case futureAI
}

/// A word of the input with its position. `key` is the lowercased word
/// without edge punctuation, for matching; `text` is the word as typed.
package struct QuickAddToken: Equatable, Sendable {
    package let index: Int
    package let range: Range<String.Index>
    package let text: String
    package let key: String

    /// Splits on whitespace, keeping each word's range in `input`.
    package static func tokenize(_ input: String) -> [QuickAddToken] {
        var tokens: [QuickAddToken] = []
        var start: String.Index?
        var position = input.startIndex
        func close(at end: String.Index) {
            guard let begin = start else { return }
            let text = String(input[begin..<end])
            let key = text.trimmingCharacters(in: QuickAddVocabulary.edgePunctuation)
                .lowercased(with: TemporalLanguage.matchingLocale)
            tokens.append(QuickAddToken(index: tokens.count, range: begin..<end, text: text, key: key))
            start = nil
        }
        while position < input.endIndex {
            if input[position].isWhitespace { close(at: position) } else if start == nil { start = position }
            position = input.index(after: position)
        }
        close(at: input.endIndex)
        return tokens
    }
}

/// When a temporal piece is about: a day, or only a week / month / year
/// ("next week" is a week — "next week on Friday" narrows it to a day).
package enum TemporalGranularity: Equatable, Sendable {
    case day
    /// A bare weekday ("Friday"): a day, but one a week-level piece can move.
    case weekday(Int)
    case week
    case month
    case year
}

/// What a temporal piece contributes. Only what the source is sure of is
/// set: a lone "10 am" has a time and no day.
package struct TemporalFact: Equatable, Sendable {
    package var day: Date?
    package var granularity: TemporalGranularity = .day
    /// Hour and minute.
    package var start: DateComponents?
    /// End of a time range ("10am - 11am") — what an event needs later.
    package var end: DateComponents?
    /// A part of the day ("morning" → 09:00): used only when no time was
    /// stated.
    package var isApproximate = false
    /// The last day of a span ("fri-sun", "3-5 oct").
    package var endDay: Date?
    /// "all day" was said.
    package var isAllDay = false
    /// Minutes, when a duration was stated ("for 90 min").
    package var duration: Int?
}

/// What a recognized piece means.
/// What a quick-add sentence should become, when it says so ("t:e").
package enum QuickAddKind: String, Equatable, Sendable {
    case task, event
}

package enum QuickAddFact: Equatable, Sendable {
    /// "#name": the task list and/or the calendar of that name.
    case tag(listID: String?, calendarID: String?)
    /// "@Office", "at Starbucks", "in Room 4".
    case location(String)
    /// "t:e" / "t:t" (also "type:event", "t:task").
    case kind(QuickAddKind)
    case priority(TaskPriority)
    case recurrence(TaskRecurrenceRule)
    case alert(TaskAlert)
    case temporal(TemporalFact)
    /// A leading "+": create a task, whatever the rest looks like.
    case forceTask

    package var isTemporal: Bool {
        if case .temporal = self { return true }
        return false
    }
}

/// A recognized piece: where, what, from whom.
package struct ParsedSpan: Equatable, Sendable {
    package let range: Range<String.Index>
    package let fact: QuickAddFact
    package let source: ParseSource
    package var confidence: Double = 1

    package func overlaps(_ other: ParsedSpan) -> Bool { range.overlaps(other.range) }
}

/// A Reminders list Quick Add can file into (`#work`).
package struct QuickAddList: Equatable, Sendable {
    package let id: String
    package let title: String
}

/// The parsed result, provider-independent: the Quick Add UI fills itself
/// from this whether it came from these extractors or, later, an AI.
package struct QuickAddDraft: Equatable, Sendable {
    /// The task's title: event-only pieces (a place, a calendar-only tag)
    /// stay in it, since a task has nowhere else to keep them.
    package var title: String
    /// The event's title: without the place and the calendar tag.
    package var eventTitle = ""
    /// Start of the due day.
    package var day: Date?
    package var startTime: DateComponents?
    package var endTime: DateComponents?
    /// Last day of a multi-day span (events; a task keeps its start day).
    package var endDay: Date?
    /// "all day", or a span of days without times (events).
    package var isAllDay = false
    /// Minutes, when a duration was stated ("for 90 min") — so an event
    /// knows its length was given, not defaulted.
    package var duration: Int?
    package var listID: String?
    /// The calendar a "#name" named (events).
    package var calendarID: String?
    /// Where (events): "@Office", "at Starbucks".
    package var location: String?
    /// Said outright with "t:e" / "t:t" (or a leading "+": task).
    package var forcedKind: QuickAddKind?
    /// Worded as a to-do: "todo …", "remind me to …".
    package var saysTask = false
    package var priority: TaskPriority = .none
    package var recurrence: TaskRecurrenceRule?
    package var alert: TaskAlert?
    /// 0…1: how sure we are the text means "create a task".
    package var confidence: Double
    /// Provenance: every piece that was recognized and removed.
    package var spans: [ParsedSpan]

    /// The due moment: the day, at the start time when there is one.
    package func dueDate(calendar: Calendar) -> Date? {
        guard let day else { return nil }
        guard let hour = startTime?.hour else { return day }
        return calendar.date(bySettingHour: hour, minute: startTime?.minute ?? 0, second: 0, of: day)
    }

    /// An event's length when only its start was said.
    package static let defaultEventMinutes = 60

    /// The event this text describes. No day → today; no time → all day;
    /// no end → the stated duration, else an hour.
    package func eventDraft(calendar: Calendar, referenceDate: Date) -> EventDraft {
        let first = day ?? calendar.startOfDay(for: referenceDate)
        let last = endDay ?? first
        let title = eventTitle.isEmpty ? self.title : eventTitle
        let alerts: [EventAlert] = alert.map { alert in
            switch alert {
            case .relative(let minutes): [.before(minutes: minutes)]
            case .absolute(let date): [.at(date)]
            }
        } ?? []
        func at(_ time: DateComponents, on day: Date) -> Date {
            calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
        }
        guard let startTime, startTime.hour != nil else {
            return EventDraft(title: title, start: first, end: last, isAllDay: true, calendarIdentifier: calendarID,
                              location: location, recurrenceRule: recurrence, alerts: alerts)
        }
        let start = at(startTime, on: first)
        var end: Date
        if let endTime, endTime.hour != nil {
            end = at(endTime, on: last)
            // "22-01": past midnight.
            if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        } else {
            let minutes = duration ?? Self.defaultEventMinutes
            end = calendar.date(byAdding: .minute, value: minutes, to: at(startTime, on: last)) ?? start
        }
        return EventDraft(title: title, start: start, end: end, calendarIdentifier: calendarID,
                          location: location, recurrenceRule: recurrence, alerts: alerts)
    }

    /// The draft the task provider creates from.
    package func taskDraft(calendar: Calendar) -> TaskDraft {
        TaskDraft(
            title: title, listID: listID, dueDate: dueDate(calendar: calendar),
            hasDueTime: startTime?.hour != nil, priority: priority,
            recurrenceRule: recurrence, alert: alert
        )
    }
}
