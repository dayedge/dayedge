import Foundation
import Domain

/// One search result as a row shows it: an event occurrence or a task.
package enum SearchResult: Hashable, Identifiable {
    case event(AgendaEventModel)
    case task(TaskItem)

    package var id: String {
        switch self {
        case .event(let event): return "event:\(event.id)"
        case .task(let task): return "task:\(task.id)"
        }
    }

    package var isTask: Bool {
        if case .task = self { return true }
        return false
    }
}

/// A result placed in the palette preview: its day (nil for an undated
/// task) and how its date tile reads.
package struct SearchResultRowItem: Hashable, Identifiable {
    package let result: SearchResult
    package let day: Date?
    /// Every dated result carries its date tile; undated tasks leave the
    /// column empty.
    package var showsDateTile: Bool { day != nil }
    package let isToday: Bool
    /// Shown with a short year ("Oct ’25").
    package let isOutsideCurrentYear: Bool

    package var id: String { result.id }
}

/// Everything a search matched, without loading it: event row ids and
/// starts (from the calendar index) and the matching tasks (already in
/// memory), in the agenda's order and grouped by day. Full events are
/// loaded by id only for what's on screen.
package struct SearchIndex: Equatable {
    package enum Entry: Hashable {
        case event(id: Int64, start: Date, isAllDay: Bool)
        case task(TaskItem)

        package var eventID: Int64? {
            if case .event(let id, _, _) = self { return id }
            return nil
        }
    }

    /// A day with results (nil: the trailing undated tasks).
    package struct Day: Hashable, Identifiable {
        package let day: Date?
        package let range: Range<Int>
        package let eventCount: Int
        package let taskCount: Int

        package var id: String { day.map { "day:\($0.timeIntervalSince1970)" } ?? "no-date" }
    }

    package var entries: [Entry] = []
    package var days: [Day] = []
    /// Where browsing starts: the first day on or after today, else the
    /// last dated day.
    package var anchorDayIndex: Int?
    /// Each event's position in `entries`.
    package var eventPositions: [Int64: Int] = [:]

    package static let empty = SearchIndex()

    package var total: Int { entries.count }
    package var isEmpty: Bool { entries.isEmpty }
    package var anchorEntryIndex: Int? { anchorDayIndex.map { days[$0].range.lowerBound } }

    /// The day `entry` falls in.
    package func dayIndex(containing entry: Int) -> Int? {
        var low = 0, high = days.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if days[mid].range.upperBound <= entry { low = mid + 1 } else if days[mid].range.lowerBound > entry { high = mid - 1 } else { return mid }
        }
        return nil
    }

    // swiftlint:disable cyclomatic_complexity function_body_length - one pass that keys, sorts and groups every entry
    /// Within a day, as the agenda: all-day events, untimed tasks, then
    /// everything timed by time (events first on a tie). Undated tasks last
    /// (open before completed).
    /// Browsing starts at today (or the nearest day before it, if all are
    /// past) — or, `anchorsAtStart` (a date-filtered query), at the first day.
    package static func build(matches: [SearchMatch], tasks: [TaskItem], now: Date, calendar: Calendar,
                              anchorsAtStart: Bool = false) -> SearchIndex {
        struct Keyed {
            let entry: Entry
            let day: Date
            let group: Int
            let time: Date
            let kind: Int
            let tie: SearchEntryTie
        }
        var keyed: [Keyed] = []
        var datedTaskCount = 0
        for task in tasks where task.dueDate != nil { datedTaskCount += 1 }
        keyed.reserveCapacity(matches.count + datedTaskCount)
        for match in matches {
            keyed.append(Keyed(entry: .event(id: match.id, start: match.start, isAllDay: match.isAllDay),
                               day: calendar.startOfDay(for: match.start), group: match.isAllDay ? 0 : 2,
                               time: match.start, kind: 0, tie: .event(match.id)))
        }
        var undated: [TaskItem] = []
        for task in tasks {
            guard let due = task.dueDate else {
                undated.append(task)
                continue
            }
            keyed.append(Keyed(entry: .task(task), day: calendar.startOfDay(for: due), group: task.hasDueTime ? 2 : 1,
                               time: due, kind: 1, tie: .task(task.title + task.id)))
        }
        keyed.sort {
            let lhs = ($0.day, $0.group, $0.time, $0.kind)
            let rhs = ($1.day, $1.group, $1.time, $1.kind)
            return lhs == rhs ? $0.tie.precedes($1.tie) : lhs < rhs
        }
        undated.sort {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }

        var index = SearchIndex()
        index.entries.reserveCapacity(keyed.count + undated.count)
        for item in keyed { index.entries.append(item.entry) }
        for task in undated { index.entries.append(.task(task)) }
        var start = 0
        while start < keyed.count {
            var end = start
            var events = 0
            while end < keyed.count, keyed[end].day == keyed[start].day {
                if keyed[end].kind == 0 { events += 1 }
                end += 1
            }
            index.days.append(Day(day: keyed[start].day, range: start..<end, eventCount: events, taskCount: end - start - events))
            start = end
        }
        if !undated.isEmpty {
            index.days.append(Day(day: nil, range: keyed.count..<index.entries.count, eventCount: 0, taskCount: undated.count))
        }
        if anchorsAtStart {
            index.anchorDayIndex = index.days.isEmpty ? nil : 0
        } else {
            let today = calendar.startOfDay(for: now)
            for (position, day) in index.days.enumerated() {
                guard let date = day.day else { continue }
                index.anchorDayIndex = position
                if date >= today { break }
            }
            if index.anchorDayIndex == nil, !index.days.isEmpty { index.anchorDayIndex = 0 }
        }
        index.eventPositions.reserveCapacity(matches.count)
        for (position, entry) in index.entries.enumerated() {
            if let id = entry.eventID { index.eventPositions[id] = position }
        }
        return index
    }
    // swiftlint:enable cyclomatic_complexity function_body_length
}

/// Same-time order between search entries: events (by id) before tasks.
private enum SearchEntryTie {
    case event(Int64)
    case task(String)

    func precedes(_ other: SearchEntryTie) -> Bool {
        switch (self, other) {
        case let (.event(lhs), .event(rhs)):
            // Equivalent to the old zero-padded decimal strings:
            // negatives first, ordered by increasing magnitude.
            if (lhs < 0) != (rhs < 0) { return lhs < 0 }
            return lhs < 0 ? lhs.magnitude < rhs.magnitude : lhs < rhs
        case let (.task(lhs), .task(rhs)): return lhs < rhs
        case (.event, .task): return true
        case (.task, .event): return false
        }
    }
}
