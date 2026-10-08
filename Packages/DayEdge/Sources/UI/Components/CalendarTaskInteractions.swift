import SwiftUI
import Domain

/// The details popover and right-click menu every calendar task carries —
/// one implementation for agenda rows, the day view's untimed rows and its
/// timed markers.
package struct CalendarTaskInteractions: ViewModifier {
    package let task: TaskItem
    /// The day this occurrence is shown on.
    package let day: Date
    package let coordinator: CalendarTaskCoordinator
    package var arrowEdge: Edge = .leading
    /// False in a calendar view that is mounted but hidden: the shared
    /// "presented task" must only open a popover in the visible one.
    package var isActive = true
    package let onComplete: () -> Void

    private var actions: TaskActions { coordinator.actions }

    package func body(content: Content) -> some View {
        let isReadOnly = actions.isReadOnly(task)
        let occurrence = CalendarTaskCoordinator.Occurrence(taskID: task.id, day: day)
        content
            .popover(
                isPresented: Binding(
                    get: { isActive && coordinator.isPresented(occurrence) },
                    set: { coordinator.setDetailPresented($0, for: occurrence) }
                ),
                arrowEdge: arrowEdge
            ) {
                TaskDetailPopoverView(
                    task: actions.task(task.id) ?? task,
                    lists: actions.repository.lists,
                    onEdit: { actions.edit($0, taskID: task.id) },
                    onToggleCompleted: onComplete,
                    isReadOnly: isReadOnly
                )
            }
            .contextMenu {
                TaskContextMenuItems(task: task, isReadOnly: isReadOnly, context: .calendar) { action in
                    if action == .complete { onComplete() } else { actions.perform(action, on: task, day: day) }
                }
            }
    }
}

extension View {
    package func calendarTaskInteractions(_ task: TaskItem, day: Date, coordinator: CalendarTaskCoordinator,
                                          arrowEdge: Edge = .leading, isActive: Bool = true,
                                          onComplete: @escaping () -> Void) -> some View {
        modifier(CalendarTaskInteractions(task: task, day: day, coordinator: coordinator, arrowEdge: arrowEdge,
                                          isActive: isActive, onComplete: onComplete))
    }
}
