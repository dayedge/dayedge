import Foundation
import Domain

/// `task_recurrence`: how a repeating task repeats — its rule, when it ends,
/// and its dates in a period, past and future. Past dates are the ones the
/// rule scheduled; the source doesn't record which of them were completed,
/// and the answer says so.
package enum TaskRecurrenceTool {
    package static let maxDays = 366
    package static let maxOccurrences = 20
    /// Default window: a month back, two months ahead.
    package static let defaultDaysBack = 28
    package static let defaultDaysAhead = 56

    package static func make(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "task_recurrence",
            description: "How a repeating task repeats: its rule, when it ends, and its past and upcoming dates.",
            parameters: [
                .init(name: "task", kind: .string, description: "The task's title, or its reference like T2."),
                .init(name: "when", kind: .string,
                      description: "Which dates to list: \(AssistantWhen.accepted). Default: 4 weeks back to 8 weeks ahead.",
                      isRequired: false)
            ]
        ) { arguments in
            let name = try arguments.string("task")
            var range: DateInterval?
            if let when = arguments.optionalString("when") { range = try await AssistantWhen.resolve(when, context: context) }
            return await answer(task: name, in: range, context: context)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity - one branch per argument and repeat case
    package static func answer(task name: String, in requested: DateInterval?, context: AssistantToolContext) async -> String {
        let calendar = context.calendar
        let now = context.now()
        let snapshot = await context.data.taskSnapshot()

        let task: TaskItem
        switch find(name, in: snapshot.tasks, context: context) {
        case .found(let found): task = found
        case .none: return "No task matching “\(name)”."
        case .several(let candidates):
            let lines = candidates.prefix(5).map { context.taskLine($0, day: nil, list: snapshot.listName(for: $0)) }
            return context.listing(["Several tasks match “\(name)”; which one?"] + lines)
        }

        let heading = context.taskLine(task, day: nil, list: snapshot.listName(for: task))
        guard let rule = task.effectiveRecurrenceRule else { return "\(heading)\n“\(task.title)” doesn't repeat." }
        guard let due = task.dueDate else { return "\(heading)\nIt repeats (\(rule.assistantSummary)) but has no due date to count from." }
        guard !rule.hasUnsupportedParts else {
            return "\(heading)\nIt repeats (\(rule.assistantSummary)) on a schedule DayEdge can't project into dates."
        }

        let today = calendar.startOfDay(for: now)
        let range = clamp(requested ?? defaultRange(today: today, calendar: calendar), calendar: calendar)
        let dates = rule.occurrences(in: range, anchoredAt: due, notBefore: task.creationDate, calendar: calendar)
        let dueDay = calendar.startOfDay(for: due)

        var lines = [heading, "Repeats: \(rule.assistantSummary). \(ending(of: rule, calendar: calendar))"]
        if let created = task.creationDate { lines.append("Created \(AssistantFormat.dayTitle(created, calendar: calendar)).") }
        let period = AssistantFormat.period(range, calendar: calendar)
        if dates.isEmpty {
            lines.append("No dates in \(period).")
        } else {
            lines.append("Dates in \(period):")
            lines += dates.prefix(maxOccurrences).map { day in
                var line = "- " + AssistantFormat.shortDay(day, calendar: calendar)
                if task.hasDueTime { line += " " + AssistantFormat.time(due, calendar: calendar) }
                if day == dueDay { line += task.isCompleted ? " · last due" : " · next due" } else if day == today { line += " · today" } else if day < today { line += " · past" }
                return line
            }
            if dates.count > maxOccurrences { lines.append("…and \(dates.count - maxOccurrences) more") }
        }
        if dates.contains(where: { $0 < dueDay }) {
            lines.append("Past dates follow the rule; Reminders doesn't record which of them were completed.")
        }
        return context.listing(lines)
    }

    // MARK: - Finding the task

    package enum Match {
        case found(TaskItem)
        case none
        case several([TaskItem])
    }

    /// A reference ("T2", "[[T2]]") first; then the title — exact, else
    /// contained — preferring repeating, open tasks when that settles it.
    package static func find(_ name: String, in tasks: [TaskItem], context: AssistantToolContext) -> Match {
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "[] ").union(.whitespacesAndNewlines))
        if case .task(let reference)? = context.references.reference(for: trimmed),
           let task = tasks.first(where: { $0.id == reference.id }) {
            return .found(task)
        }
        let needle = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !needle.isEmpty else { return .none }
        func folded(_ task: TaskItem) -> String { task.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let exact = tasks.filter { folded($0) == needle }
        let candidates = exact.isEmpty ? tasks.filter { folded($0).contains(needle) } : exact
        let preferred = candidates.filter { $0.isRecurring && !$0.isCompleted }
        let pool = preferred.isEmpty ? candidates : preferred
        switch pool.count {
        case 0: return .none
        case 1: return .found(pool[0])
        default: return .several(pool)
        }
    }

    // MARK: - Helpers

    private static func defaultRange(today: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -defaultDaysBack, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: defaultDaysAhead + 1, to: today) ?? today
        return DateInterval(start: start, end: end)
    }

    private static func clamp(_ range: DateInterval, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: range.start)
        let limit = calendar.date(byAdding: .day, value: maxDays, to: start) ?? range.end
        return DateInterval(start: start, end: min(range.end, limit))
    }

    private static func ending(of rule: TaskRecurrenceRule, calendar: Calendar) -> String {
        if let end = rule.endDate { return "Ends on \(AssistantFormat.dayTitle(end, calendar: calendar))." }
        if let count = rule.occurrenceCount { return "Ends after \(count) times." }
        return "No end date."
    }
}
