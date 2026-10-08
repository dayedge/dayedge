import Foundation
import Domain

/// A semantic answer to “where should an agenda orient around now?” Views
/// deliberately render these cases differently: Month inserts a compact
/// synthetic row, while Day reuses its real hour-grid Now indicator.
package enum AgendaNowTarget: Equatable, Hashable, Sendable {
    /// `nextItemID` is an event id, or `AgendaItemID.task(_:)` when the next
    /// timed thing is a task.
    case gap(nextItemID: String?, until: Date?)
    case ongoing(eventIDs: [String])
    case endOfDay
    case day

    package func statusLabel(calendar: Calendar = .autoupdatingCurrent, format: TimeFormat = .twentyFourHour) -> String? {
        switch self {
        case .gap(_, let until?):
            return L10n.tr("agendanowtarget.free.until", "Free until \(String(describing: format.time(until, calendar: calendar)))")
        case .ongoing(let eventIDs):
            return eventIDs.count == 1 ? L10n.tr("agendanowtarget.in.progress", "In progress") : "\(eventIDs.count) ongoing"
        case .gap, .endOfDay, .day:
            return nil
        }
    }

    package var ongoingEventIDs: Set<String> {
        guard case .ongoing(let eventIDs) = self else { return [] }
        return Set(eventIDs)
    }

}

package struct AgendaNowPresentation: Equatable {
    package let day: Date
    package let minute: Date
    package let target: AgendaNowTarget
}

/// Ids of the agenda's timed items. Event ids are EventKit's own; tasks are
/// namespaced so the two can never collide.
package enum AgendaItemID {
    package static func task(_ id: String) -> String { "task:" + id }
}

// swiftlint:disable cyclomatic_complexity - the Now policy: ongoing, then next event or task, then end of day
/// Pure, reusable positioning policy shared by Month and Day agendas.
/// `timedTasks` are points in time: they can end a "Free until" gap but are
/// never "ongoing".
package func preferredNowTarget(
    on day: Date,
    events: [AgendaEventModel],
    timedTasks: [TaskItem] = [],
    now: Date,
    calendar: Calendar = .autoupdatingCurrent
) -> AgendaNowTarget {
    let dayStart = calendar.startOfDay(for: day)
    let minute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
    let intervals = events.compactMap { event -> (event: AgendaEventModel, interval: DateInterval)? in
        guard event.status != .cancelled,
              !event.isAllDay,
              let interval = agendaInterval(for: event, on: dayStart, calendar: calendar) else { return nil }
        return (event, interval)
    }

    let ongoingIDs = intervals
        .filter { $0.interval.start <= minute && minute < $0.interval.end }
        .sorted {
            if $0.interval.start == $1.interval.start { return $0.event.id < $1.event.id }
            return $0.interval.start < $1.interval.start
        }
        .map(\.event.id)
    if !ongoingIDs.isEmpty {
        return .ongoing(eventIDs: ongoingIDs)
    }

    let taskPoints = timedTasks.compactMap { task -> (id: String, start: Date)? in
        guard let due = task.dueDate, task.hasDueTime, calendar.isDate(due, inSameDayAs: dayStart) else { return nil }
        return (AgendaItemID.task(task.id), due)
    }
    guard !intervals.isEmpty || !taskPoints.isEmpty else { return .day }

    let nextEvent = intervals
        .filter { $0.interval.start > minute }
        .min {
            if $0.interval.start == $1.interval.start { return $0.event.id < $1.event.id }
            return $0.interval.start < $1.interval.start
        }
        .map { (id: $0.event.id, start: $0.interval.start) }
    // A task due this very minute is "now", not upcoming.
    let nextTask = taskPoints.filter { $0.start > minute }.min { $0.start < $1.start }
    // On a tie the event comes first, as it does in the agenda's order.
    let next: (id: String, start: Date)?
    switch (nextEvent, nextTask) {
    case let (event?, task?): next = task.start < event.start ? task : event
    case let (event?, nil): next = event
    case let (nil, task?): next = task
    case (nil, nil): next = nil
    }
    if let next {
        return .gap(nextItemID: next.id, until: next.start)
    }
    return .endOfDay
}
// swiftlint:enable cyclomatic_complexity
