import Foundation

/// `get_current_date`: the date and time right now, from the clock — not
/// from the conversation, which may have started on another day. For the
/// model to check itself before it says "today" or "tomorrow".
package enum CurrentDateTool {
    package static func make(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "get_current_date",
            description: "The current date, time and week, from the clock. Use it to check which day it is now; earlier messages may be from another day.",
            parameters: []
        ) { _ in
            answer(now: context.now(), calendar: context.calendar)
        }
    }

    package static func answer(now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        var lines = [
            "Now: \(AssistantInstructions.longDate(now, calendar: calendar)), \(AssistantInstructions.time(now, calendar)) "
                + "(\(AssistantInstructions.isoDay(now, calendar)), time zone \(calendar.timeZone.identifier))",
            "Yesterday: \(AssistantInstructions.longDate(day(-1), calendar: calendar))",
            "Tomorrow: \(AssistantInstructions.longDate(day(1), calendar: calendar))"
        ]
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            let last = week.end.addingTimeInterval(-1)
            lines.append("This week: \(AssistantInstructions.isoDay(week.start, calendar)) to \(AssistantInstructions.isoDay(last, calendar))")
        }
        return lines.joined(separator: "\n")
    }
}
