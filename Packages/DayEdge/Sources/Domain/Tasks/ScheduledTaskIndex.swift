import Foundation

/// What one calendar day shows of the user's reminders. Tasks are actions,
/// not events: untimed ones sit above the day's chronology, timed ones join
/// it as points in time.
package struct DayTasks: Equatable, Sendable {
    /// Today only: open tasks whose due day has already passed, oldest first.
    package var overdue: [TaskItem] = []
    /// Due this day with no time.
    package var untimed: [TaskItem] = []
    /// Due this day at a time, in time order.
    package var timed: [TaskItem] = []
    /// Later occurrences of repeating tasks, computed for this day (not the
    /// reminder's real due date). Shown, but completing applies only to the
    /// current occurrence, so these can't be ticked off from here.
    package var projectedIDs: Set<String> = []

    package static let none = DayTasks()

    package var count: Int { overdue.count + untimed.count + timed.count }
    package var isEmpty: Bool { count == 0 }
    /// Overdue first, then the day's own untimed tasks.
    package var allUntimed: [TaskItem] { overdue + untimed }
    /// The task the day's agenda lists first.
    package var first: TaskItem? { overdue.first ?? untimed.first ?? timed.first }
}

/// Open, scheduled reminders bucketed by due day — built once per data
/// change, then read per day in O(1) plus a check of the few repeating
/// tasks. EventKit keeps one due date per reminder (a repeating one carries
/// only its next occurrence); later occurrences are computed for the day
/// being read, never generated or stored ahead.
package struct ScheduledTaskIndex: Equatable, Sendable {
    /// Identifies the data this was built from; equality is only this, so
    /// views can compare indexes cheaply.
    package let signature: Int
    private let today: Date
    private let byDay: [Date: DayTasks]
    private let overdue: [TaskItem]
    private let repeating: [RepeatingTask]

    /// A repeating task and the rule its later occurrences follow.
    private struct RepeatingTask: Sendable {
        let task: TaskItem
        let rule: TaskRecurrenceRule
        let dueDay: Date
        /// Occurrences are shown only after this day: after the real due
        /// day, and never on today or earlier (an overdue task shows once,
        /// as overdue; history isn't projected).
        let after: Date
        let hour: Int
        let minute: Int
    }

    package static let empty = ScheduledTaskIndex(signature: 0, today: .distantPast, byDay: [:], overdue: [], repeating: [])

    private init(signature: Int, today: Date, byDay: [Date: DayTasks], overdue: [TaskItem], repeating: [RepeatingTask]) {
        self.signature = signature
        self.today = today
        self.byDay = byDay
        self.overdue = overdue
        self.repeating = repeating
    }

    /// `signature` must change whenever `tasks` or `now`'s day does.
    package init(tasks: [TaskItem], now: Date, calendar: Calendar, signature: Int) {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: DayTasks] = [:]
        var overdue: [TaskItem] = []
        var repeating: [RepeatingTask] = []

        for task in tasks where !task.isCompleted {
            guard let due = task.dueDate else { continue }
            let day = calendar.startOfDay(for: due)
            if let rule = task.effectiveRecurrenceRule {
                let parts = calendar.dateComponents([.hour, .minute], from: due)
                repeating.append(RepeatingTask(
                    task: task, rule: rule, dueDay: day, after: max(day, today),
                    hour: parts.hour ?? 0, minute: parts.minute ?? 0
                ))
            }
            if day < today {
                overdue.append(task)
            } else if task.hasDueTime {
                byDay[day, default: .none].timed.append(task)
            } else {
                byDay[day, default: .none].untimed.append(task)
            }
        }

        for day in byDay.keys {
            byDay[day]?.timed.sort(by: Self.timedOrder)
            byDay[day]?.untimed.sort(by: Self.untimedOrder)
        }
        overdue.sort {
            if $0.dueDate != $1.dueDate { return ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
            return Self.untimedOrder($0, $1)
        }

        self.init(signature: signature, today: today, byDay: byDay, overdue: overdue, repeating: repeating)
    }

    package func tasks(on day: Date, calendar: Calendar = .autoupdatingCurrent) -> DayTasks {
        let start = calendar.startOfDay(for: day)
        var result = byDay[start] ?? .none
        if start == today { result.overdue = overdue }

        var projectedTimed = false
        var projectedUntimed = false
        for item in repeating where start > item.after && item.rule.occurs(on: start, startingAt: item.dueDay, calendar: calendar) {
            var occurrence = item.task
            occurrence.dueDate = item.task.hasDueTime
                ? calendar.date(bySettingHour: item.hour, minute: item.minute, second: 0, of: start)
                : start
            result.projectedIDs.insert(occurrence.id)
            if occurrence.hasDueTime {
                result.timed.append(occurrence); projectedTimed = true
            } else {
                result.untimed.append(occurrence); projectedUntimed = true
            }
        }
        if projectedTimed { result.timed.sort(by: Self.timedOrder) }
        if projectedUntimed { result.untimed.sort(by: Self.untimedOrder) }
        return result
    }

    package static func == (lhs: ScheduledTaskIndex, rhs: ScheduledTaskIndex) -> Bool {
        lhs.signature == rhs.signature
    }

    private static func timedOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.dueDate != b.dueDate { return (a.dueDate ?? .distantPast) < (b.dueDate ?? .distantPast) }
        return untimedOrder(a, b)
    }

    /// Higher priority first, then the source's own order.
    private static func untimedOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.priority != b.priority { return a.priority.rawValue > b.priority.rawValue }
        if a.sourceOrder != b.sourceOrder { return a.sourceOrder < b.sourceOrder }
        return a.id < b.id
    }
}

/// "1 event · 5 tasks" — zero parts left out.
package enum DayCountLabel {
    package static func text(events: Int, tasks: Int, locale: Locale = AppLocalization.displayLocale) -> String? {
        var parts: [String] = []
        if events > 0 { parts.append(L10n.tr("day.count.events", "\(events) events", locale: locale)) }
        if tasks > 0 { parts.append(L10n.tr("day.count.tasks", "\(tasks) tasks", locale: locale)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Where keyboard selection goes when the selected item disappears (a task
/// just completed): the next item at the same position, else the previous
/// one, else nothing.
package enum SelectionSuccessor {
    package static func after<ID: Equatable>(removing removed: ID, in order: [ID]) -> ID? {
        guard let index = order.firstIndex(of: removed) else { return nil }
        if index + 1 < order.count { return order[index + 1] }
        if index > 0 { return order[index - 1] }
        return nil
    }
}
