import Foundation

/// A point in time from a tool argument: "tomorrow 15:00", "friday 3pm",
/// "2026-10-02 09:30", "2026-10-02T09:30", "15:00". The day goes through
/// `AssistantWhen` (the app's parsers, never the model's arithmetic); the
/// time is read here.
package struct AssistantMoment: Equatable, Sendable {
    package let date: Date
    /// False for a day without a time ("tomorrow").
    package let hasTime: Bool

    package struct NeedsDay: Error, Equatable {
        package let text: String
    }

    package static let accepted = "a day with an optional time, like 'tomorrow', 'friday 15:00', '2026-10-02 09:30'"

    /// `day` is used for a time on its own ("15:00" when moving an event:
    /// that event's day); without one, a time alone is asked back.
    package static func resolve(_ text: String, on day: Date? = nil, context: AssistantToolContext) async throws -> AssistantMoment {
        let calendar = context.calendar
        let (dayText, time) = split(text)
        let start: Date
        if dayText.isEmpty {
            guard let day, time != nil else { throw NeedsDay(text: text) }
            start = calendar.startOfDay(for: day)
        } else {
            start = try await AssistantWhen.resolve(dayText, context: context).start
        }
        guard let time else { return AssistantMoment(date: start, hasTime: false) }
        let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: start) ?? start
        return AssistantMoment(date: date, hasTime: true)
    }

    /// The time, if any, and what's left for the day.
    package static func split(_ text: String) -> (day: String, time: (hour: Int, minute: Int)?) {
        var lowered = text.lowercased()
        if let separator = isoTimeSeparator(in: lowered) { lowered.replaceSubrange(separator, with: " ") }
        var words = lowered.split(whereSeparator: \.isWhitespace).map(String.init)
        var time: (Int, Int)?
        var index = 0
        while index < words.count {
            var word = words[index]
            var consumed = 1
            // "3 pm" → "3pm"
            if index + 1 < words.count, ["am", "pm"].contains(words[index + 1]) {
                word += words[index + 1]
                consumed = 2
            }
            // "at 10", "o 10": after a connector, a bare hour is a time.
            let afterConnector = index > 0 && connectors.contains(words[index - 1])
            if time == nil, let parsed = clock(word) ?? (afterConnector ? bareHour(word) : nil) {
                time = parsed
                words.removeSubrange(index..<(index + consumed))
                // "at 15:00", "o 15:00"
                if index > 0, connectors.contains(words[index - 1]) {
                    words.remove(at: index - 1)
                }
                continue
            }
            index += 1
        }
        return (words.joined(separator: " ").trimmingCharacters(in: .whitespaces), time)
    }

    package static let connectors: Set<String> = ["at", "@", "o", "um", "à"]

    /// "10" → 10:00, only where it can't be a day ("at 10").
    package static func bareHour(_ word: String) -> (hour: Int, minute: Int)? {
        guard let hour = Int(word), (0...23).contains(hour) else { return nil }
        return (hour, 0)
    }

    // swiftlint:disable cyclomatic_complexity - one branch per accepted moment form
    /// "15:00", "9.30", "3pm", "3:30pm", "noon".
    package static func clock(_ word: String) -> (hour: Int, minute: Int)? {
        if word == "noon" { return (12, 0) }
        if word == "midnight" { return (0, 0) }
        var text = word
        var meridiem: String?
        for suffix in ["am", "pm"] where text.hasSuffix(suffix) {
            meridiem = suffix
            text.removeLast(2)
        }
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == "." }).map(String.init)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              var hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) ?? -1 : 0
        // A bare number is a day or a count, not a time — unless it says am/pm.
        if parts.count == 1, meridiem == nil { return nil }
        if parts.count == 2, parts[1].count != 2 { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour != 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
    // swiftlint:enable cyclomatic_complexity

    /// "2026-10-02t09:30": the "t" between an ISO date and a time.
    private static func isoTimeSeparator(in text: String) -> Range<String.Index>? {
        guard let match = text.range(of: #"\d{4}-\d{2}-\d{2}t\d"#, options: .regularExpression) else { return nil }
        let t = text.index(match.lowerBound, offsetBy: 10)
        return t..<text.index(after: t)
    }
}
