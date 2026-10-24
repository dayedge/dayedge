import Foundation

/// A date or range the parser read, in the app's terms: "next week", "friday 3pm", "2026-10-01..2026-10-07".
package struct ParsedDate: Equatable, Sendable {
    /// What the text named: a day, a week, a month or a year.
    package enum Span: Equatable, Sendable { case day, week, month, year }

    package let start: Date
    /// Exclusive; equal to `start` for a point in time.
    package let end: Date
    package let span: Span
    /// A time was given ("friday 3pm"), not only a day.
    package let hasTime: Bool

    package init(start: Date, end: Date, span: Span, hasTime: Bool = false) {
        self.start = start
        self.end = end
        self.span = span
        self.hasTime = hasTime
    }
}

/// The first date inside longer text, and the text without it: "standup tomorrow" → tomorrow, "standup".
package struct FoundDate: Equatable, Sendable {
    package let date: ParsedDate
    package let remainingText: String

    package init(date: ParsedDate, remainingText: String) {
        self.date = date
        self.remainingText = remainingText
    }
}
