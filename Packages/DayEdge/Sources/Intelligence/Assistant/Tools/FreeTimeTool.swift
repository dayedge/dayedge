import Foundation
import Domain

/// `find_free_time`: open slots within working hours, between timed events.
/// Over several days, weekends are left out.
package enum FreeTimeTool {
    package static let maxDays = 14
    package static let defaultMinutes = 30

    package static func make(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "find_free_time",
            description: "Free time slots between the user's events, within working hours.",
            parameters: [
                .init(name: "when", kind: .string, description: "Which days: \(AssistantWhen.accepted). Default today.", isRequired: false),
                .init(name: "minutes", kind: .integer, description: "Shortest useful slot in minutes. Default 30.", isRequired: false)
            ]
        ) { arguments in
            let interval = try await AssistantWhen.resolve(arguments.optionalString("when") ?? "today", context: context)
            let minutes = arguments.integer("minutes", in: 5...1440) ?? defaultMinutes
            return await answer(for: interval, minutes: minutes, context: context)
        }
    }

    package static func answer(for interval: DateInterval, minutes: Int, context: AssistantToolContext) async -> String {
        let calendar = context.calendar
        let now = context.now()
        var days = AssistantWhen.days(in: interval, calendar: calendar, limit: maxDays)
        if days.count > 1 { days.removeAll { calendar.isDateInWeekend($0) } }
        let windows = days.compactMap { day in FreeTimeFinder.workingWindow(on: day, now: now, calendar: calendar).map { (day, $0) } }
        guard let first = windows.first?.0, let last = windows.last?.0,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else {
            return "No working time left in \(AssistantFormat.period(interval, calendar: calendar))."
        }

        let sections = await context.data.agenda(in: DateInterval(start: first, end: end), calendar: calendar)
        let busy = FreeTimeFinder.busyIntervals(sections.flatMap(\.events))
        let holidays = await context.data.holidays(in: DateInterval(start: first, end: end), calendar: calendar)
        var lines = ["Free time (\(hours) working hours, at least \(minutes) min):"]
        for (day, window) in windows {
            let gaps = FreeTimeFinder.gaps(in: window, busy: busy, minimum: TimeInterval(minutes * 60))
            let slots = gaps.map { "\(AssistantFormat.time($0.start, calendar: calendar))–\(AssistantFormat.time($0.end, calendar: calendar))" }
            let text = "\(AssistantFormat.dayTitle(day, calendar: calendar)): \(slots.isEmpty ? "no free slot" : slots.joined(separator: ", "))"
            lines.append(context.dayLine(day, holidays: holidays, text: text))
        }
        return AssistantFormat.capped(lines, max: context.maxLines)
    }

    private static var hours: String {
        String(format: "%02d:00–%02d:00", FreeTimeFinder.workdayStartHour, FreeTimeFinder.workdayEndHour)
    }
}
