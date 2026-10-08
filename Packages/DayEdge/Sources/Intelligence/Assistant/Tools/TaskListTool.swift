import Foundation
import Domain
import UI

/// `list_tasks`: the user's tasks by state, optionally in one list —
/// including those not tied to any day, which `get_agenda` can't show.
package enum TaskListTool {
    /// What `recent` means: added within this many days.
    package static let recentDays = 7

    package enum Filter: String, CaseIterable {
        case open, overdue, undated, repeating, recent, completed
    }

    package static func make(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "list_tasks",
            description: "The user's tasks: open, overdue, without a date, repeating, recently added (newest first), or recently completed.",
            parameters: [
                .init(name: "filter", kind: .string, description: "Which tasks. Default open.", isRequired: false,
                      enumValues: Filter.allCases.map(\.rawValue)),
                .init(name: "list", kind: .string, description: "Only this list, by name. Omit for all lists.", isRequired: false)
            ]
        ) { arguments in
            let filter = arguments.optionalString("filter").flatMap(Filter.init) ?? .open
            return await answer(filter: filter, list: arguments.optionalString("list"), context: context)
        }
    }

    package static func answer(filter: Filter, list listName: String?, context: AssistantToolContext) async -> String {
        let calendar = context.calendar
        let now = context.now()
        let snapshot = await context.data.taskSnapshot()

        var tasks = snapshot.tasks
        var scope = "all lists"
        if let listName, !listName.isEmpty {
            guard let list = snapshot.lists.first(where: { $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame }) else {
                return "No list named “\(listName)”. Lists: \(snapshot.lists.map(\.title).joined(separator: ", "))."
            }
            tasks = tasks.filter { $0.listID == list.id }
            scope = list.title
        }
        tasks = tasks.filter { task in
            switch filter {
            case .open: return !task.isCompleted
            case .overdue: return !task.isCompleted && TaskBuckets.isOverdue(task, now: now, calendar: calendar)
            case .undated: return !task.isCompleted && task.dueDate == nil
            case .repeating: return !task.isCompleted && task.isRecurring
            case .recent: return task.creationDate.map { $0 >= recentSince(now: now, calendar: calendar) } ?? false
            case .completed: return task.isCompleted
            }
        }
        guard !tasks.isEmpty else { return "No \(filter.rawValue) tasks in \(scope)." }

        let sorted = filter == .recent ? tasks.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
                                       : tasks.sorted(by: order)
        var listing = AssistantListing(maxLines: context.maxLines)
        listing.append("\(filter.rawValue.capitalized) tasks in \(scope) (\(tasks.count)):")
        for task in sorted { listing.append(line(task, snapshot: snapshot, context: context)) }
        return context.listing(listing)
    }

    private static func line(_ task: TaskItem, snapshot: AssistantTaskSnapshot, context: AssistantToolContext) -> String {
        let line = context.taskLine(task, day: nil, list: snapshot.listName(for: task))
        return task.creationDate.map { line + " · added \(AssistantFormat.date($0, calendar: context.calendar))" } ?? line
    }

    private static func recentSince(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -recentDays, to: calendar.startOfDay(for: now)) ?? now
    }

    /// Soonest due first (undated last), then higher priority, then the
    /// source's order.
    private static func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if a.priority != b.priority { return a.priority.rawValue > b.priority.rawValue }
        return a.sourceOrder < b.sourceOrder
    }
}
