import Foundation

/// `get_current_date`: the date and time right now, from the clock — not
/// from the conversation, which may have started on another day. For the
/// model to check itself before it says "today" or "tomorrow".
package enum CurrentDateTool {
    package static func make(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "get_current_date",
            description: "The current date and time, from the clock, with the dates around it to pass to the tools. "
                + "Use it to check which day it is now; earlier messages may be from another day.",
            parameters: []
        ) { _ in
            answer(now: context.now(), calendar: context.calendar)
        }
    }

    package static func answer(now: Date, calendar: Calendar) -> String {
        "Now: \(AssistantInstructions.longDate(now, calendar: calendar)), \(AssistantInstructions.time(now, calendar)) "
            + "(\(AssistantInstructions.isoDay(now, calendar)), time zone \(calendar.timeZone.identifier))\n"
            + AssistantInstructions.dates(now: now, calendar: calendar, days: 15)
    }
}
