import Foundation

/// `get_days`: what the days of a period are — public holidays (in the
/// user's holiday region), weekends, workdays. For "is Friday a holiday?",
/// "how do the holidays fall at Christmas?", "long weekends in May?". Up to
/// a month, every day is listed; over a longer period, only the holidays.
package enum DaysTool {
    package static let everyDayLimit = 31
    package static let maxDays = 366
    package static let defaultWhen = "next 30 days"

    package static func make(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "get_days",
            description: "What the days of a period are: public holidays, weekends and workdays.",
            parameters: [
                .init(name: "when", kind: .string,
                      description: "Which days: \(AssistantWhen.accepted). Default next 30 days.", isRequired: false)
            ]
        ) { arguments in
            let interval = try await AssistantWhen.resolve(arguments.optionalString("when") ?? defaultWhen, context: context)
            return await answer(for: interval, context: context)
        }
    }

    package static func answer(for interval: DateInterval, context: AssistantToolContext) async -> String {
        let calendar = context.calendar
        let days = AssistantWhen.days(in: interval, calendar: calendar, limit: maxDays)
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return "That period has no days." }
        let covered = DateInterval(start: first, end: end)
        let holidays = await context.data.holidays(in: covered, calendar: calendar)
        let period = AssistantFormat.period(covered, calendar: calendar)

        let region = holidays.region.map { Locale.current.localizedString(forRegionCode: $0) ?? $0 }
        let everyDay = days.count <= everyDayLimit
        let listed = everyDay ? days : days.filter { holidays.name(for: $0, calendar: calendar) != nil }
        let lines = listed.map { day -> String in
            var text = "\(AssistantFormat.shortDay(day, calendar: calendar)) \(calendar.component(.year, from: day))"
            if let holiday = holidays.name(for: day, calendar: calendar) {
                text += " · \(holiday) (public holiday)"
                if holidays.isWeekend(day, calendar: calendar) { text += " · weekend" }
            } else {
                text += holidays.isWeekend(day, calendar: calendar) ? " · weekend" : " · workday"
            }
            return context.dayLine(day, holidays: holidays, text: text)
        }

        var heading = everyDay ? "Days in \(period)" : "Public holidays in \(period)"
        heading += region.map { " (holidays for \($0))" } ?? " (no holiday region set in Settings → Calendars)"
        guard !lines.isEmpty else { return "\(heading): none." }
        return context.showsReferences
            ? AssistantFormat.capped([heading + ":"] + lines, max: everyDayLimit + 1) + "\n" + dayHint
            : AssistantFormat.capped([heading + ":"] + lines, max: everyDayLimit + 1)
    }

    /// How days are shown — at the end of the result, where small models
    /// and big ones both look.
    package static let dayHint = "To show days to the user, write their references together on one line, like [[D1]] [[D2]] [[D3]]; "
        + "the app displays them as dates. Don't retype the dates."
}
