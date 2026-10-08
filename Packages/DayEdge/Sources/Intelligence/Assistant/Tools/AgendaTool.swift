import Foundation
import Domain

/// `get_agenda`: a day's or period's events and scheduled tasks, the way
/// the agenda shows them (overdue tasks on today).
package enum AgendaTool {
    package static let maxDays = 31

    package static func make(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "get_agenda",
            description: "The user's calendar events and scheduled tasks for a day or period.",
            parameters: [
                .init(name: "when", kind: .string, description: "Which days: \(AssistantWhen.accepted). Default today.", isRequired: false)
            ]
        ) { arguments in
            let interval = try await AssistantWhen.resolve(arguments.optionalString("when") ?? "today", context: context)
            return await answer(for: interval, context: context)
        }
    }

    package static func answer(for interval: DateInterval, context: AssistantToolContext) async -> String {
        let calendar = context.calendar
        let now = context.now()
        let days = AssistantWhen.days(in: interval, calendar: calendar, limit: maxDays)
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return "That period has no days." }
        let covered = DateInterval(start: first, end: end)

        let sections = await context.data.agenda(in: covered, calendar: calendar)
        let snapshot = await context.data.taskSnapshot()
        let holidays = await context.data.holidays(in: covered, calendar: calendar)
        var eventsByDay: [Date: [AgendaEventModel]] = [:]
        for section in sections { eventsByDay[calendar.startOfDay(for: section.date), default: []] += section.events }
        let tasks = ScheduledTaskIndex(tasks: snapshot.tasks, now: now, calendar: calendar, signature: 0)

        let period = AssistantFormat.period(covered, calendar: calendar)
        var listing = AssistantListing(maxLines: context.maxLines)
        listing.append("Agenda for \(period):")
        for day in days {
            let events = eventsByDay[day] ?? []
            let dayTasks = tasks.tasks(on: day, calendar: calendar)
            let holiday = holidays.name(for: day, calendar: calendar)
            guard !events.isEmpty || !dayTasks.isEmpty || holiday != nil else { continue }
            listing.append(dayLine(day, holiday: holiday, holidays: holidays, context: context))
            for event in events { listing.append(context.eventLine(event, day: day)) }
            for task in dayTasks.overdue { listing.append(context.taskLine(task, day: day, list: snapshot.listName(for: task))) }
            for task in dayTasks.untimed + dayTasks.timed {
                listing.append(context.taskLine(task, day: day, list: snapshot.listName(for: task), showsDay: false))
            }
        }
        guard listing.count > 1 else { return "Nothing scheduled for \(period)." }
        if interval.end > covered.end { listing.append("(Only the first \(maxDays) days.)") }
        return context.listing(listing)
    }

    private static func dayLine(_ day: Date, holiday: String?, holidays: AssistantHolidays, context: AssistantToolContext) -> String {
        var title = AssistantFormat.dayTitle(day, calendar: context.calendar)
        if let holiday { title += " · \(holiday) (public holiday)" }
        return context.dayLine(day, holidays: holidays, text: title)
    }
}
