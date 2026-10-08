import Foundation
import Domain

/// Pure agenda-positioning logic split out of `AgendaListView` — ordering
/// a day's rows around the NOW marker, and resolving a scroll target to the
/// anchor to scroll to. Neither depends on `View` or `ScrollViewProxy`, so
/// both are directly testable. The same row order drives rendering and
/// keyboard navigation, so the two can never disagree.
package enum AgendaSectionProjection {
    package struct TimedRow: Identifiable {
        package let id: AgendaScrollAnchor
        package let kind: AgendaTimedRowKind
    }

    /// A section's rows below its all-day events: untimed tasks (overdue
    /// first), then NOW, then timed events and timed tasks in time order.
    /// All-day events aren't part of this — they render as their own group.
    /// On a tie an event comes before a task.
    package static func rows(
        section: AgendaDaySection,
        tasks: DayTasks = .none,
        nowPresentation: AgendaNowPresentation?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [TimedRow] {
        let sectionID = section.id
        let untimed = tasks.overdue.map { taskRow($0, sectionID: sectionID, overdue: true) }
            + tasks.untimed.map { taskRow($0, sectionID: sectionID, overdue: false) }

        // Most month-agenda sections already have their final event order.
        // Only timed tasks or NOW need per-day minutes and merge bookkeeping.
        if tasks.timed.isEmpty, nowPresentation == nil {
            return untimed + section.events.filter { !$0.isAllDay }.map { event in
                TimedRow(id: .event(sectionID: sectionID, eventID: event.id),
                         kind: .event(event, isOngoing: false))
            }
        }
        let items = timedItems(section: section, tasks: tasks, calendar: calendar)
        guard let presentation = nowPresentation else {
            return untimed + items.map { $0.row([]) }
        }
        return untimed + placingNow(presentation, among: items, sectionID: sectionID, calendar: calendar)
    }

    /// Timed events and timed tasks with their minute on this day, merged
    /// stably (an event before a task on a tie).
    private static func timedItems(section: AgendaDaySection, tasks: DayTasks, calendar: Calendar) -> [TimedItem] {
        let sectionID = section.id
        let dayStart = calendar.startOfDay(for: section.date)
        let items: [TimedItem] = section.events.filter { !$0.isAllDay }.map { event in
            TimedItem(itemID: event.id, minute: startMinute(of: event, on: dayStart, calendar: calendar)) { ongoing in
                TimedRow(id: .event(sectionID: sectionID, eventID: event.id),
                         kind: .event(event, isOngoing: ongoing.contains(event.id)))
            }
        }
        guard !tasks.timed.isEmpty else { return items }
        var merged: [TimedItem] = []
        merged.reserveCapacity(items.count + tasks.timed.count)
        var taskIndex = 0
        let timed = tasks.timed.map { task in
            TimedItem(itemID: AgendaItemID.task(task.id), minute: minutes(of: task.dueDate ?? dayStart, calendar: calendar)) { _ in
                taskRow(task, sectionID: sectionID, overdue: false)
            }
        }
        for item in items {
            while taskIndex < timed.count, timed[taskIndex].minute < item.minute {
                merged.append(timed[taskIndex]); taskIndex += 1
            }
            merged.append(item)
        }
        merged.append(contentsOf: timed[taskIndex...])
        return merged
    }

    /// The timed rows with NOW where its target says: before the next item
    /// (a gap), among the ongoing ones, at the end of the day, or not at all.
    private static func placingNow(_ presentation: AgendaNowPresentation, among items: [TimedItem], sectionID: Date,
                                   calendar: Calendar) -> [TimedRow] {
        let nowRow = TimedRow(id: .now(sectionID: sectionID), kind: .now(presentation))

        switch presentation.target {
        case .gap(let nextItemID, _):
            let splitIndex = nextItemID.flatMap { id in items.firstIndex(where: { $0.itemID == id }) } ?? items.endIndex
            return items[..<splitIndex].map { $0.row([]) }
                + [nowRow]
                + items[splitIndex...].map { $0.row([]) }

        case .ongoing(let eventIDs):
            let activeIDs = Set(eventIDs)
            let markerMinutes = minutes(of: presentation.minute, calendar: calendar)
            let inactive = items.filter { !activeIDs.contains($0.itemID) }
            let past = inactive.filter { $0.minute < markerMinutes }
            let future = inactive.filter { $0.minute >= markerMinutes }
            let active = items.filter { activeIDs.contains($0.itemID) }
            return past.map { $0.row([]) }
                + [nowRow]
                + active.map { $0.row(activeIDs) }
                + future.map { $0.row([]) }

        case .endOfDay:
            return items.map { $0.row([]) } + [nowRow]

        case .day:
            return items.map { $0.row([]) }
        }
    }

    /// Keyboard order over the rows' events and tasks (NOW is skipped).
    package static func itemAnchors(in rows: [TimedRow]) -> [AgendaScrollAnchor] {
        rows.map(\.id).filter(\.isItem)
    }

    /// The day view's keyboard order: the whole day as one sequence —
    /// all-day events, untimed tasks, then timed events and tasks in time
    /// order — so ↑ / ↓ cross from the top area into the grid seamlessly.
    package static func dayItemAnchors(section: AgendaDaySection, tasks: DayTasks) -> [AgendaScrollAnchor] {
        section.events.filter(\.isAllDay).map { .event(sectionID: section.id, eventID: $0.id) }
            + itemAnchors(in: rows(section: section, tasks: tasks, nowPresentation: nil))
    }

    private static func taskRow(_ task: TaskItem, sectionID: Date, overdue: Bool) -> TimedRow {
        TimedRow(id: .task(sectionID: sectionID, taskID: task.id), kind: .task(task, isOverdue: overdue))
    }

    /// Where an event starts on this day: a span that began earlier starts
    /// at midnight here.
    private static func startMinute(of event: AgendaEventModel, on dayStart: Date, calendar: Calendar) -> Int {
        if event.startDate != nil, let interval = agendaInterval(for: event, on: dayStart, calendar: calendar) {
            return Int(interval.start.timeIntervalSince(dayStart) / 60)
        }
        return event.startMinutesSinceMidnight ?? Int.max
    }

    /// Resolves a scroll target to the anchor `AgendaListView` should
    /// scroll to.
    package static func anchor(
        for target: AgendaScrollTarget,
        in sections: [AgendaDaySection],
        nowPresentation: AgendaNowPresentation?,
        tasks: (Date) -> DayTasks = { _ in .none }
    ) -> AgendaScrollAnchor? {
        let calendar = Calendar.autoupdatingCurrent
        guard let section = sections.first(where: { calendar.isDate($0.date, inSameDayAs: target.date) }) else { return nil }

        if let nowTarget = target.nowTarget {
            switch nowTarget {
            case .gap, .ongoing:
                // When NOW is the section's first row, targeting the marker
                // itself puts it underneath the pinned day header. The
                // section anchor keeps both header and marker visible.
                let presentation = AgendaNowPresentation(
                    day: section.date,
                    minute: nowPresentation?.minute ?? section.date,
                    target: nowTarget
                )
                let rows = rows(section: section, tasks: tasks(section.date), nowPresentation: presentation)
                if case .now = rows.first?.kind { return .day(section.id) }
                return .now(sectionID: section.id)
            case .endOfDay:
                return .now(sectionID: section.id)
            case .day:
                return .day(section.id)
            }
        }
        if let eventID = target.eventID,
           section.events.contains(where: { $0.id == eventID }) {
            return .event(sectionID: section.id, eventID: eventID)
        }
        if let taskID = target.taskID {
            let dayTasks = tasks(section.date)
            if (dayTasks.allUntimed + dayTasks.timed).contains(where: { $0.id == taskID }) {
                return .task(sectionID: section.id, taskID: taskID)
            }
        }
        return .day(section.id)
    }

    private static func minutes(of date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

/// What a timed agenda row shows.
package enum AgendaTimedRowKind {
    case event(AgendaEventModel, isOngoing: Bool)
    case task(TaskItem, isOverdue: Bool)
    case now(AgendaNowPresentation)
}

/// A timed event or task with its minute on the day, and how to make its row.
private struct TimedItem {
    let itemID: String
    let minute: Int
    let row: (Set<String>) -> AgendaSectionProjection.TimedRow
}
