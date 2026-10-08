import Foundation
import Domain

/// Where timed tasks sit on the day view's hour grid. A task is a point in
/// time: its card is placed so the completion ring lies exactly on the due
/// minute's line, and its height is the card's own (content), never a
/// duration. Cards that would overlap (same or nearby times) stack
/// downward. Pure, computed once per data change.
package enum DayTaskMarkerLayout {
    package struct Marker: Identifiable, Equatable {
        package var id: String { task.id }
        package let task: TaskItem
        /// The due minute's position on the grid.
        package let anchorY: CGFloat
        /// The card's top (≥ `anchorY - ringCenter`).
        package let y: CGFloat
        package let height: CGFloat

        /// The grid span the card occupies, in minutes, for collision layout
        /// with events.
        package func span(minuteHeight: CGFloat) -> DayTimelineLayout.TaskSpan {
            let start = Int((y / minuteHeight).rounded(.down))
            let end = Int(((y + height) / minuteHeight).rounded(.up))
            return DayTimelineLayout.TaskSpan(id: task.id, startMinutes: start, endMinutes: max(end, start + 1))
        }
    }

    /// `height` is each task's own card height (its content's).
    package static func layout(tasks: [TaskItem], minuteHeight: CGFloat, gap: CGFloat, ringCenter: CGFloat,
                               calendar: Calendar = .autoupdatingCurrent, height: (TaskItem) -> CGFloat) -> [Marker] {
        var result: [Marker] = []
        var nextFreeY = -CGFloat.infinity
        let placed = tasks
            .compactMap { task -> (TaskItem, CGFloat)? in
                guard task.hasDueTime, let due = task.dueDate else { return nil }
                let parts = calendar.dateComponents([.hour, .minute], from: due)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                return (task, CGFloat(minutes) * minuteHeight)
            }
            .sorted { $0.1 < $1.1 }
        for (task, anchorY) in placed {
            // Never above the grid's top edge.
            let cardHeight = height(task)
            let y = max(anchorY - ringCenter, nextFreeY, 0)
            result.append(Marker(task: task, anchorY: anchorY, y: y, height: cardHeight))
            nextFreeY = y + cardHeight + gap
        }
        return result
    }
}
