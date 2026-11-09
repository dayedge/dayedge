import Foundation
import Domain

/// Which tasks Tasks shows: Today, the next 7 days or all of them. A filter
/// over the reminders, then the `TaskBuckets` grouping — its sections (the
/// lists; on All Tasks also Needs attention and Completed) are reached by
/// jumping.
package enum TaskFilter: Hashable, CaseIterable {
    case today
    case nextWeek
    case all

    package var smartView: TaskSmartView {
        switch self {
        case .today: return .today
        case .nextWeek: return .nextWeek
        case .all: return .all
        }
    }

    package var title: String { smartView.title }

    /// `today` is the start of the current day. `isCompleted` is the task's
    /// state as placed: a just-ticked task stays put for a moment.
    package func includes(_ task: TaskItem, isCompleted: Bool, today: Date, calendar: Calendar) -> Bool {
        switch self {
        case .all: return true
        case _ where isCompleted: return false
        case .today: return TaskBuckets.isDue(task, by: today, calendar: calendar)
        case .nextWeek:
            let lastDay = calendar.date(byAdding: .day, value: 6, to: today) ?? today
            return TaskBuckets.isDue(task, by: lastDay, calendar: calendar)
        }
    }

    /// All Tasks keeps the document as it is; a narrower filter shows every
    /// row it holds by list — no Needs attention group (overdue and due
    /// today are both, so it would hold all of Today), no Completed.
    package func options(from base: TaskBucketOptions) -> TaskBucketOptions {
        guard self != .all else { return base }
        var options = base
        options.showsAttention = false
        options.showsCompleted = false
        options.listPreview = .max
        return options
    }

    /// How many tasks each filter holds; All Tasks counts the open ones.
    package static func counts(tasks: [TaskItem], now: Date, calendar: Calendar) -> [TaskFilter: Int] {
        let today = calendar.startOfDay(for: now)
        var counts = Dictionary(uniqueKeysWithValues: allCases.map { ($0, 0) })
        for task in tasks where !task.isCompleted {
            for filter in allCases where filter.includes(task, isCompleted: false, today: today, calendar: calendar) {
                counts[filter, default: 0] += 1
            }
        }
        return counts
    }
}

extension TaskSmartView {
    /// The filter it picks; Needs Attention is a section, not a filter.
    package var filter: TaskFilter? {
        switch self {
        case .attention: return nil
        case .today: return .today
        case .nextWeek: return .nextWeek
        case .all: return .all
        }
    }
}
