import SwiftUI
import Domain

package struct TaskSection: Identifiable {
    package enum Kind: Hashable {
        case needsAttention
        case list(String)
        case completed
        case results
    }

    package let kind: Kind
    package let title: String
    package let color: Color?
    /// Every task that belongs here, including ones not shown.
    package let totalCount: Int
    /// The rows actually shown.
    package let tasks: [TaskItem]
    /// How many rows the collapsed preview shows; nil when the section is
    /// never folded (completed, search results).
    package var previewLimit: Int?

    package var hiddenCount: Int { totalCount - tasks.count }
    /// More tasks than the preview shows, so "Show N more" applies.
    package var canExpand: Bool { previewLimit.map { totalCount > $0 } ?? false }
    package var isExpanded: Bool { canExpand && hiddenCount == 0 }

    /// A landmark in the continuous document (Needs attention, a list, or
    /// the trailing Completed group), as opposed to search results.
    package var isNavigable: Bool {
        switch kind {
        case .needsAttention, .list, .completed: return true
        case .results: return false
        }
    }

    /// Short chip label ("Needs attention" reads "Attention" in the rail).
    package var navigatorTitle: String { kind == .needsAttention ? L10n.tr("taskbuckets.attention", "Attention") : title }

    package var id: String {
        switch kind {
        case .needsAttention: return "attention"
        case .list(let id): return "list-\(id)"
        case .completed: return "completed"
        case .results: return "results"
        }
    }
}

package struct TaskBucketOptions: Equatable {
    /// Preview limits: a big list stays a glanceable landmark until the
    /// user expands it.
    package static let attentionPreview = 6
    package static let listPreview = 5
    package static let completedBatch = 15

    /// Ids (`TaskSection.id`) of sections shown in full.
    package var expandedSectionIDs: Set<String> = []
    package var completedExpanded = false
    /// The app smart sections can be hidden: without Attention its tasks
    /// stay in their lists; without Completed those tasks aren't shown.
    package var showsAttention = true
    package var showsCompleted = true
    /// How many completed tasks show once Completed is expanded; grows in
    /// batches of `completedBatch` ("Show more").
    package var completedLimit: Int = Self.completedBatch
    /// Order inside ordinary list sections only.
    package var sortMode: TaskSortMode = .smart
    package var sortDirection: TaskSortDirection = .ascending
    package var attentionPreview: Int = Self.attentionPreview
    package var listPreview: Int = Self.listPreview

    package init(
        expandedSectionIDs: Set<String> = [],
        completedExpanded: Bool = false,
        showsAttention: Bool = true,
        showsCompleted: Bool = true,
        completedLimit: Int = Self.completedBatch,
        sortMode: TaskSortMode = .smart,
        sortDirection: TaskSortDirection = .ascending,
        attentionPreview: Int = Self.attentionPreview,
        listPreview: Int = Self.listPreview
    ) {
        self.expandedSectionIDs = expandedSectionIDs
        self.completedExpanded = completedExpanded
        self.showsAttention = showsAttention
        self.showsCompleted = showsCompleted
        self.completedLimit = completedLimit
        self.sortMode = sortMode
        self.sortDirection = sortDirection
        self.attentionPreview = attentionPreview
        self.listPreview = listPreview
    }
}

package struct TaskDueText: Equatable {
    package let text: String
    package let isOverdue: Bool

    package init(text: String, isOverdue: Bool) {
        self.text = text
        self.isOverdue = isOverdue
    }
}

/// Pure "what needs my attention" logic. Tasks is one continuous document:
/// Needs attention, then one section per list, then Completed. Each task
/// lands in exactly one section, and big sections are bounded previews
/// until expanded.
package enum TaskBuckets {
    package static func sections(
        tasks: [TaskItem],
        lists: [CalendarSource],
        now: Date,
        calendar: Calendar,
        options: TaskBucketOptions = .init(),
        lingeringIDs: Set<String> = [],
        placementOverrides: [String: TaskItem] = [:]
    ) -> [TaskSection] {
        let today = calendar.startOfDay(for: now)

        var attention: [TaskItem] = [], completed: [TaskItem] = []
        var byList: [String: [TaskItem]] = [:]

        for task in tasks {
            // Placement uses the task as it was when its details opened, so
            // editing a date/priority/list doesn't pull the row (and its
            // popover) out from under the user; it settles on close.
            let placed = placementOverrides[task.id] ?? task
            // A just-toggled task keeps the bucket it was in for a moment,
            // so the row doesn't jump the instant it is checked.
            let isDone = lingeringIDs.contains(task.id) ? !task.isCompleted : placed.isCompleted
            if isDone {
                completed.append(task)
            } else if options.showsAttention && needsAttention(placed, today: today, calendar: calendar) {
                attention.append(task)
            } else {
                byList[placed.listID, default: []].append(task)
            }
        }

        var result: [TaskSection] = []
        func add(_ kind: TaskSection.Kind, _ title: String, color: Color? = nil, _ items: [TaskItem], previewLimit: Int) {
            guard !items.isEmpty else { return }
            let probe = TaskSection(kind: kind, title: title, color: color, totalCount: items.count, tasks: [], previewLimit: previewLimit)
            let shown = options.expandedSectionIDs.contains(probe.id) ? items : Array(items.prefix(previewLimit))
            result.append(TaskSection(
                kind: kind, title: title, color: color, totalCount: items.count, tasks: shown, previewLimit: previewLimit
            ))
        }

        add(.needsAttention, L10n.tr("taskbuckets.needs.attention", "Needs attention"), ranked(attention, today: today, calendar: calendar, placement: placementOverrides),
            previewLimit: options.attentionPreview)
        for list in lists {
            add(.list(list.id), list.title, color: list.color,
                TaskSorter.sort(
                    byList[list.id] ?? [], mode: options.sortMode, direction: options.sortDirection,
                    today: today, calendar: calendar, placement: placementOverrides
                ),
                previewLimit: options.listPreview)
        }
        if options.showsCompleted { addCompleted(completed, options: options, into: &result) }
        return result
    }

    private static func addCompleted(_ completed: [TaskItem], options: TaskBucketOptions, into result: inout [TaskSection]) {
        guard !completed.isEmpty else { return }
        // Most recently completed first; stable for equal dates.
        let sorted = completed.sorted {
            let (a, b) = ($0.completionDate ?? .distantPast, $1.completionDate ?? .distantPast)
            return a != b ? a > b : $0.id < $1.id
        }
        result.append(TaskSection(
            kind: .completed, title: L10n.tr("taskbuckets.completed", "Completed"), color: nil, totalCount: sorted.count,
            tasks: options.completedExpanded ? Array(sorted.prefix(options.completedLimit)) : [], previewLimit: nil
        ))
    }

    /// One flat section over every list — search never depends on scope.
    /// Open tasks first (ranked), then completed ones.
    package static func searchResults(
        tasks: [TaskItem], query: String, now: Date, calendar: Calendar
    ) -> [TaskSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let matching = tasks.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.notes?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
        guard !matching.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        let open = ranked(matching.filter { !$0.isCompleted }, today: today, calendar: calendar)
        let done = matching.filter(\.isCompleted)
            .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
        let all = open + done
        return [TaskSection(kind: .results, title: L10n.tr("taskbuckets.results", "Results"), color: nil, totalCount: all.count, tasks: all, previewLimit: nil)]
    }

    package static func needsAttention(_ task: TaskItem, today: Date, calendar: Calendar) -> Bool {
        if task.priority == .high { return true }
        guard let due = task.dueDate else { return false }
        return calendar.startOfDay(for: due) <= today
    }

    package static func attentionCount(tasks: [TaskItem], now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        return tasks.filter { !$0.isCompleted && needsAttention($0, today: today, calendar: calendar) }.count
    }

    /// What "Today's Tasks" counts: open tasks that are overdue or due
    /// today — not every open reminder, and not undated high priority ones.
    package static func actionableTodayCount(tasks: [TaskItem], now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        return tasks.filter { task in
            guard !task.isCompleted, let due = task.dueDate else { return false }
            return calendar.startOfDay(for: due) <= today
        }.count
    }

    package static func isOverdue(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        guard let due = task.dueDate else { return false }
        if task.hasDueTime { return due < now }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    /// "Today", "Yesterday", "Sep 23" — when a completed task was finished.
    package static func completionText(for task: TaskItem, now: Date, calendar: Calendar,
                                       dates: DatePresentationFormatter = .current) -> String? {
        guard let completedAt = task.completionDate else { return nil }
        let delta = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: completedAt), to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch delta {
        case 0: return L10n.tr("taskbuckets.today", "Today")
        case 1: return L10n.tr("taskbuckets.yesterday", "Yesterday")
        default: return dates.with(calendar).format(completedAt, .short, relativeTo: now)
        }
    }

    /// "Today 14:00" (or "Today 2:00pm"), "Tomorrow", "Sep 28", "Overdue 2 days". nil when undated.
    package static func dueText(for task: TaskItem, now: Date, calendar: Calendar,
                                format: TimeFormat = .twentyFourHour, dates: DatePresentationFormatter = .current) -> TaskDueText? {
        guard let due = task.dueDate else { return nil }
        let today = calendar.startOfDay(for: now)
        let delta = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? 0
        let time = task.hasDueTime ? " " + format.time(due, calendar: calendar) : ""

        if delta < 0 {
            let days = -delta
            return TaskDueText(text: L10n.tr("tasks.overdue.days", "Overdue \(days) days"), isOverdue: true)
        }
        switch delta {
        case 0: return TaskDueText(text: L10n.tr("taskbuckets.today", "Today") + time, isOverdue: isOverdue(task, now: now, calendar: calendar))
        case 1: return TaskDueText(text: L10n.tr("taskbuckets.tomorrow", "Tomorrow") + time, isOverdue: false)
        default:
            let date = dates.with(calendar).format(due, .short, relativeTo: now)
            return TaskDueText(text: date + time, isOverdue: false)
        }
    }

    /// Urgency order — always used by Needs attention and search, whatever
    /// the user's sort (see `TaskSorter.smartOrder`).
    package static func ranked(_ tasks: [TaskItem], today: Date, calendar: Calendar,
                               placement: [String: TaskItem] = [:]) -> [TaskItem] {
        TaskSorter.sort(tasks, mode: .smart, today: today, calendar: calendar, placement: placement)
    }
}
