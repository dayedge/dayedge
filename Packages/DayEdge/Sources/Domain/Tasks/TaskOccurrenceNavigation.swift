import Foundation

/// Previous / next occurrence of a repeating task, among the days the
/// calendar actually shows it on — the same set `ScheduledTaskIndex`
/// produces: the real occurrence (on its due day, or on today while
/// overdue), then the rule's later days. Earlier history isn't shown, so
/// it isn't navigated to. The counterpart of `EventKitOccurrenceFinder`
/// for tasks: same horizon, same "not found" outcome.
package enum TaskOccurrenceNavigation {
    /// Where the real (current) occurrence is shown.
    package static func shownDay(of task: TaskItem, now: Date, calendar: Calendar) -> Date? {
        guard let due = task.dueDate else { return nil }
        return max(calendar.startOfDay(for: due), calendar.startOfDay(for: now))
    }

    package static func adjacentDay(
        for task: TaskItem,
        from day: Date,
        direction: OccurrenceDirection,
        now: Date,
        calendar: Calendar,
        horizonYears: Int = AppConfiguration.recurrenceNavigationHorizonYears
    ) -> Date? {
        guard !task.isCompleted, let due = task.dueDate, let rule = task.effectiveRecurrenceRule,
              let current = shownDay(of: task, now: now, calendar: calendar) else { return nil }
        let dueDay = calendar.startOfDay(for: due)
        let from = calendar.startOfDay(for: day)
        func isShown(_ candidate: Date) -> Bool {
            candidate == current || (candidate > current && rule.occurs(on: candidate, startingAt: dueDay, calendar: calendar))
        }

        switch direction {
        case .next:
            if from < current { return current }
            guard let limit = calendar.date(byAdding: .year, value: horizonYears, to: from) else { return nil }
            var candidate = from
            while let next = calendar.date(byAdding: .day, value: 1, to: candidate), next <= limit {
                candidate = next
                if isShown(candidate) { return candidate }
            }
            return nil
        case .previous:
            guard from > current else { return nil }
            var candidate = from
            while let previous = calendar.date(byAdding: .day, value: -1, to: candidate), previous >= current {
                candidate = previous
                if isShown(candidate) { return candidate }
            }
            return nil
        }
    }
}
