import Foundation
import Domain

/// Computes side-by-side column positions for overlapping events in a day
/// timeline, the same way Google Calendar/Apple Calendar do it:
///
/// 1. Walk events sorted by start time, grouping them into "clusters" of
///    transitively overlapping events (if A overlaps B and B overlaps C,
///    all three share a cluster even if A and C don't directly overlap).
/// 2. Within a cluster, greedily assign each event to the first column
///    whose previous occupant has already ended — the standard interval
///    graph coloring approach. Every event in a cluster shares that
///    cluster's column count, so they all end up the same width.
///
/// This is a pure function (no view/geometry code) so it can be tested and
/// reused regardless of how pixels-per-minute or column width are chosen.
package enum DayTimelineLayout {
    package struct PositionedEvent: Identifiable {
        /// The event's own (per-occurrence) id — stable across layouts. A
        /// fresh id per layout made SwiftUI rebuild every event block on
        /// each re-render, cancelling a drag in progress mid-gesture.
        package var id: String { event.id }
        package let event: AgendaEventModel
        package let startMinutes: Int
        package let endMinutes: Int
        package let columnIndex: Int
        package let columnCount: Int
    }

    /// A timed task's card on the grid, in minutes — a point in time
    /// with the card's own height, taking part in collisions so it never
    /// overlaps an event block.
    package struct TaskSpan: Equatable {
        package let id: String
        package let startMinutes: Int
        package let endMinutes: Int
    }

    package struct PositionedTask: Equatable {
        package let columnIndex: Int
        package let columnCount: Int
    }

    package static func layout(events: [AgendaEventModel], day: Date, calendar: Calendar = .autoupdatingCurrent) -> [PositionedEvent] {
        layout(events: events, tasks: [], day: day, calendar: calendar).events
    }

    /// Events and task cards share the lane: overlapping ones get columns
    /// side by side, exactly like overlapping events. On a tie a task comes
    /// first (leftmost, next to its time).
    package static func layout(events: [AgendaEventModel], tasks: [TaskSpan], day: Date,
                               calendar: Calendar = .autoupdatingCurrent) -> (events: [PositionedEvent], tasks: [String: PositionedTask]) {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)

        let timedEvents = events
            .compactMap { event -> TimelineItem? in
                guard !event.isAllDay else { return nil }
                // Prefer the event's real, absolute instants, clipped to
                // this displayed day's boundaries — this is what lets a
                // crossing-midnight or multi-day event actually appear
                // (clipped) on every day it occupies, instead of only its
                // literal start day. Falls back to the old same-day-only
                // "HH:mm" reconstruction for data with no real dates
                // (mock/legacy), preserving today's behavior there.
                if let start = event.startDate, let end = event.endDate, let dayEnd {
                    guard start < dayEnd, end > dayStart else { return nil }
                    let clippedStart = Int(max(start, dayStart).timeIntervalSince(dayStart) / 60)
                    let clippedEnd = Int(min(end, dayEnd).timeIntervalSince(dayStart) / 60)
                    guard clippedEnd > clippedStart else { return nil }
                    return TimelineItem(kind: .event(event), start: clippedStart, end: clippedEnd)
                }
                guard let start = event.startMinutesSinceMidnight,
                      let end = event.endMinutesSinceMidnight,
                      end > start else { return nil }
                return TimelineItem(kind: .event(event), start: start, end: end)
            }
        let timed = (tasks.map { TimelineItem(kind: .task($0.id), start: $0.startMinutes, end: $0.endMinutes) } + timedEvents)
            .enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)

        let result = placeInColumns(timed)

        var positionedEvents: [PositionedEvent] = []
        var positionedTasks: [String: PositionedTask] = [:]
        for placed in result {
            let item = placed.item
            switch item.kind {
            case .event(let event):
                positionedEvents.append(PositionedEvent(event: event, startMinutes: item.start,
                                                        endMinutes: item.end, columnIndex: placed.column, columnCount: placed.count))
            case .task(let id):
                positionedTasks[id] = PositionedTask(columnIndex: placed.column, columnCount: placed.count)
            }
        }
        return (positionedEvents, positionedTasks)
    }

    /// Overlapping items (by start order) form a cluster; each cluster
    /// gets its own columns.
    private static func placeInColumns(_ timed: [TimelineItem]) -> [PlacedItem] {
        var result: [PlacedItem] = []
        var cluster: [TimelineItem] = []
        var clusterEnd = Int.min

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            result.append(contentsOf: assignColumns(cluster))
            cluster.removeAll()
        }

        for item in timed {
            if item.start >= clusterEnd {
                flushCluster()
                clusterEnd = item.end
            } else {
                clusterEnd = max(clusterEnd, item.end)
            }
            cluster.append(item)
        }
        flushCluster()
        return result
    }

    private static func assignColumns(_ items: [TimelineItem]) -> [PlacedItem] {
        var columnEnds: [Int] = []
        var assigned: [(TimelineItem, Int)] = []

        for item in items {
            if let freeColumn = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[freeColumn] = item.end
                assigned.append((item, freeColumn))
            } else {
                columnEnds.append(item.end)
                assigned.append((item, columnEnds.count - 1))
            }
        }

        let columnCount = columnEnds.count
        return assigned.map { PlacedItem(item: $0.0, column: $0.1, count: columnCount) }
    }
}

/// An event or a timed task on the timeline, in minutes since midnight.
private struct TimelineItem {
    let kind: TimelineItemKind
    let start: Int
    let end: Int
}

private enum TimelineItemKind {
    case event(AgendaEventModel)
    case task(String)
}

/// An item with its column in its overlap cluster.
private struct PlacedItem {
    let item: TimelineItem
    let column: Int
    let count: Int
}
