import Foundation

/// A point in time from a tool argument: "2026-10-02", "2026-10-02 09:30" (or "2026-10-02T09:30"), or "09:30" on a day
/// the tool already has. Read exactly; the model copies days from its instructions rather than working them out.
package struct AssistantMoment: Equatable, Sendable {
    package let date: Date
    /// False for a day without a time.
    package let hasTime: Bool

    package struct NeedsDay: Error, Equatable {
        package let text: String
    }

    package static let accepted = "a day as 2026-10-02, or a day and 24-hour time as 2026-10-02 15:00"

    /// When changing something that has a moment already (`existing`): a time alone goes on its day ("15:00" keeps the
    /// day), and with `keepsTime`, a day alone keeps its time ("2026-10-05" keeps 15:00). Without one, a time alone is
    /// asked back.
    package static func resolve(_ text: String, on existing: Date? = nil, keepsTime: Bool = false,
                                context: AssistantToolContext) throws -> AssistantMoment {
        let calendar = context.calendar
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "T" }).map(String.init)
        func at(_ time: (hour: Int, minute: Int), on day: Date) throws -> AssistantMoment {
            guard let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) else {
                throw AssistantWhen.Unrecognized(text: text, expected: accepted)
            }
            return AssistantMoment(date: date, hasTime: true)
        }
        if parts.count == 1, let date = AssistantDateText.day(parts[0], calendar) {
            guard keepsTime, let existing else { return AssistantMoment(date: date, hasTime: false) }
            let time = calendar.dateComponents([.hour, .minute], from: existing)
            return try at((time.hour ?? 0, time.minute ?? 0), on: date)
        }
        if parts.count == 1, let time = AssistantDateText.time(parts[0]) {
            guard let existing else { throw NeedsDay(text: text) }
            return try at(time, on: calendar.startOfDay(for: existing))
        }
        if parts.count == 2, let date = AssistantDateText.day(parts[0], calendar), let time = AssistantDateText.time(parts[1]) {
            return try at(time, on: date)
        }
        throw AssistantWhen.Unrecognized(text: text, expected: accepted)
    }
}
