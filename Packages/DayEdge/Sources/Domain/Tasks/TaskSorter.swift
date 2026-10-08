import Foundation

/// How rows are arranged inside ordinary list sections. Needs attention and
/// Completed keep their own semantic order regardless.
package enum TaskSortMode: String, CaseIterable, Identifiable, Sendable {
    case smart
    case dueDate
    case priority
    case title
    case created
    case remindersOrder

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .smart: return L10n.tr("tasksorter.smart", "Smart")
        case .dueDate: return L10n.tr("tasksorter.due.date", "Due Date")
        case .priority: return L10n.tr("tasksorter.priority", "Priority")
        case .title: return L10n.tr("tasksorter.title", "Title")
        case .created: return L10n.tr("tasksorter.created", "Created")
        case .remindersOrder: return L10n.tr("tasksorter.reminders.order", "Reminders Order")
        }
    }

    /// Compact label for the toolbar trigger.
    package var shortTitle: String { self == .remindersOrder ? L10n.tr("tasksorter.reminders", "Reminders") : title }

    /// Smart defines its own order, so it has no direction.
    package var hasDirection: Bool { self != .smart }

    /// Plain-language direction labels, so "ascending priority" never has
    /// to be decoded.
    package func directionTitle(_ direction: TaskSortDirection) -> String {
        let ascending = direction == .ascending
        switch self {
        case .smart: return ""
        case .dueDate: return ascending ? L10n.tr("tasksorter.soonest.first", "Soonest First") : L10n.tr("tasksorter.latest.first", "Latest First")
        case .priority: return ascending ? L10n.tr("tasksorter.highest.first", "Highest First") : L10n.tr("tasksorter.lowest.first", "Lowest First")
        case .title: return ascending ? "A to Z" : "Z to A"
        case .created: return ascending ? L10n.tr("tasksorter.oldest.first", "Oldest First") : L10n.tr("tasksorter.newest.first", "Newest First")
        case .remindersOrder: return ascending ? L10n.tr("tasksorter.as.in.reminders", "As in Reminders") : L10n.tr("tasksorter.reversed", "Reversed")
        }
    }
}

package enum TaskSortDirection: String, CaseIterable, Sendable {
    case ascending
    case descending
}

/// Deterministic sorting for task sections. Every mode ends in the same
/// stable tie-breakers — due date where meaningful, then the source
/// (Reminders) order, then the task id — so identical data always yields
/// identical rows. Tasks missing the sorted property always go last,
/// whatever the direction.
package enum TaskSorter {
    // swiftlint:disable:next cyclomatic_complexity - one case per sort mode, each a few lines; splitting scatters the comparator
    package static func sort(
        _ tasks: [TaskItem],
        mode: TaskSortMode,
        direction: TaskSortDirection = .ascending,
        today: Date,
        calendar: Calendar,
        placement: [String: TaskItem] = [:]
    ) -> [TaskItem] {
        func placed(_ task: TaskItem) -> TaskItem { placement[task.id] ?? task }
        let ascending = direction == .ascending

        return tasks.sorted { liveA, liveB in
            let a = placed(liveA), b = placed(liveB)
            switch mode {
            case .smart:
                if let result = smartOrder(a, b, today: today, calendar: calendar) { return result }
            case .dueDate:
                if let result = optionalOrder(a.dueDate, b.dueDate, ascending: ascending) { return result }
            case .priority:
                // Apple's priority: High is the most important. "Highest
                // first" is ascending; no priority always last.
                let (pa, pb) = (a.priority.rawValue, b.priority.rawValue)
                if (pa == 0) != (pb == 0) { return pb == 0 }
                if pa != pb { return ascending ? pa > pb : pa < pb }
            case .title:
                let order = a.title.localizedStandardCompare(b.title)
                if order != .orderedSame { return ascending ? order == .orderedAscending : order == .orderedDescending }
            case .created:
                if let result = optionalOrder(a.creationDate, b.creationDate, ascending: ascending) { return result }
            case .remindersOrder:
                if a.sourceOrder != b.sourceOrder { return ascending ? a.sourceOrder < b.sourceOrder : a.sourceOrder > b.sourceOrder }
            }
            return tieBreak(a, b)
        }
    }

    /// Urgency: overdue, due today, upcoming by date, then undated (higher
    /// priority first). Used by Smart and, always, by Needs attention.
    package static func smartOrder(_ a: TaskItem, _ b: TaskItem, today: Date, calendar: Calendar) -> Bool? {
        func group(_ task: TaskItem) -> Int {
            guard let due = task.dueDate else { return 3 }
            let day = calendar.startOfDay(for: due)
            if day < today { return 0 }
            return day == today ? 1 : 2
        }
        let (ga, gb) = (group(a), group(b))
        if ga != gb { return ga < gb }
        if let x = a.dueDate, let y = b.dueDate, x != y { return x < y }
        if a.priority != b.priority { return a.priority.rawValue > b.priority.rawValue }
        return nil
    }

    /// Present values first (in the requested direction), missing ones last.
    private static func optionalOrder(_ x: Date?, _ y: Date?, ascending: Bool) -> Bool? {
        switch (x, y) {
        case let (x?, y?) where x != y: return ascending ? x < y : x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return nil
        }
    }

    private static func tieBreak(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if let result = optionalOrder(a.dueDate, b.dueDate, ascending: true) { return result }
        if a.sourceOrder != b.sourceOrder { return a.sourceOrder < b.sourceOrder }
        return a.id < b.id
    }
}
