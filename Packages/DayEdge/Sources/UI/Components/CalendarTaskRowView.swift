import SwiftUI
import Domain

/// A task inside a calendar view (agenda, day view's untimed area): the
/// Tasks view's own row, with its details popover and menu, placed in a
/// day. Only the metadata differs — the day already says when it's due.
package struct CalendarTaskRowView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat

    package let task: TaskItem
    /// The day this occurrence is shown on.
    package let day: Date
    package let coordinator: CalendarTaskCoordinator
    /// Carried over from an earlier day (Today only).
    package var isOverdue = false
    /// Due today with no time (Today only), shown as "Today".
    package var isToday = false
    package var isKeyboardSelected = false
    package var isActive = true
    /// A later occurrence of a repeating task, computed for this day.
    /// Completing only ever applies to the current occurrence, so this one
    /// can be opened but not ticked off.
    package var isProjected = false
    package var density: AgendaRowDensity = .regular
    /// Off where a container draws the selection and owns clicks (search).
    package var drawsSelectionBackground = true
    package var opensDetailsOnTap = true
    package var compactTimeColumnWidth: CGFloat?
    package var compactTitleFades = false
    /// Completion goes through the caller, which moves keyboard selection
    /// on when the completed task was selected.
    package let onComplete: () -> Void
    package var onSelect: () -> Void = {}

    private var actions: TaskActions { coordinator.actions }

    package var body: some View {
        let list = actions.list(for: task)
        TaskRowView(
            task: task,
            listName: list?.title,
            tint: list?.color ?? theme.secondaryText,
            due: dueText,
            timeLabel: task.hasDueTime && !isOverdue ? task.dueDate.map { timeFormat.time($0) } : nil,
            isSelected: isKeyboardSelected,
            isDetailPresented: isActive && coordinator.isPresented(.init(taskID: task.id, day: day)),
            isReadOnly: actions.isReadOnly(task) || isProjected,
            style: .embedded,
            density: density,
            drawsSelectionBackground: drawsSelectionBackground,
            compactTimeColumnWidth: compactTimeColumnWidth,
            compactTitleFades: compactTitleFades,
            onToggle: onComplete,
            onTap: {
                onSelect()
                if opensDetailsOnTap { coordinator.toggleDetail(for: .init(taskID: task.id, day: day)) }
            }
        )
        .calendarTaskInteractions(task, day: day, coordinator: coordinator, isActive: isActive,
                                  onComplete: isProjected ? {} : onComplete)
    }

    private var dueText: TaskDueText? {
        if isOverdue, let due = task.dueDate {
            let days = max(Calendar.autoupdatingCurrent.dateComponents(
                [.day], from: Calendar.autoupdatingCurrent.startOfDay(for: due),
                to: Calendar.autoupdatingCurrent.startOfDay(for: Date())
            ).day ?? 1, 1)
            return TaskDueText(text: L10n.tr(
                "calendartaskrowview.overdue", "Overdue \(String(describing: days)) \(String(describing: days == 1 ? "day" : "days"))"
            ), isOverdue: true)
        }
        if isToday && !task.hasDueTime { return TaskDueText(text: L10n.tr("calendartaskrowview.today", "Today"), isOverdue: false) }
        return nil
    }

    package init(
        task: TaskItem,
        day: Date,
        coordinator: CalendarTaskCoordinator,
        isOverdue: Bool = false,
        isToday: Bool = false,
        isKeyboardSelected: Bool = false,
        isActive: Bool = true,
        isProjected: Bool = false,
        density: AgendaRowDensity = .regular,
        drawsSelectionBackground: Bool = true,
        opensDetailsOnTap: Bool = true,
        compactTimeColumnWidth: CGFloat? = nil,
        compactTitleFades: Bool = false,
        onComplete: @escaping () -> Void,
        onSelect: @escaping () -> Void = {}
    ) {
        self.task = task
        self.day = day
        self.coordinator = coordinator
        self.isOverdue = isOverdue
        self.isToday = isToday
        self.isKeyboardSelected = isKeyboardSelected
        self.isActive = isActive
        self.isProjected = isProjected
        self.density = density
        self.drawsSelectionBackground = drawsSelectionBackground
        self.opensDetailsOnTap = opensDetailsOnTap
        self.compactTimeColumnWidth = compactTimeColumnWidth
        self.compactTitleFades = compactTitleFades
        self.onComplete = onComplete
        self.onSelect = onSelect
    }
}
