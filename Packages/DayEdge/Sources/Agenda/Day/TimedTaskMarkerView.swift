import SwiftUI
import Domain
import UI

/// A timed task on the day view's hour grid: the same content as in the
/// Tasks view (`TaskRowContent` — ring, title, list, repeat, priority) on a
/// compact neutral card, anchored so the ring sits on its due minute. A
/// point in time, never a duration: the height is the content's
/// (`TimedTaskCardMetrics`), the fill is graphite (the list color stays on
/// the ring), and it is narrower than an event block.
package struct TimedTaskMarkerView: View {
    @Environment(\.themePalette) private var theme

    package let task: TaskItem
    /// The day this occurrence is shown on.
    package let day: Date
    package let coordinator: CalendarTaskCoordinator
    package var isKeyboardSelected = false
    package var isActive = true
    /// A later occurrence of a repeating task, computed for this day.
    /// Completing only ever applies to the current occurrence, so this one
    /// can be opened but not ticked off.
    package var isProjected = false
    /// Never wider than a shared column allows.
    package var minWidth: CGFloat = AppTheme.Tasks.timelineCardMinWidth
    package let onComplete: () -> Void
    package var onSelect: () -> Void = {}

    @State private var isHovering = false

    private var actions: TaskActions { coordinator.actions }
    private var isPresented: Bool { isActive && coordinator.isPresented(.init(taskID: task.id, day: day)) }

    /// Whether the card has a second line — which sets its height.
    package static func hasSecondLine(_ task: TaskItem, listName: String?) -> Bool {
        TaskRowContent.hasSecondLine(listName: listName, due: nil, task: task)
    }

    private var fill: Color {
        if isPresented { return theme.content.detailSelectionFill }
        if isKeyboardSelected { return theme.tasks.timelineCardSelectedFill }
        if isHovering { return theme.tasks.timelineCardHoverFill }
        return theme.tasks.timelineCardFill
    }

    package var body: some View {
        let list = actions.list(for: task)
        let isReadOnly = actions.isReadOnly(task) || isProjected
        let shape = RoundedRectangle(cornerRadius: AppTheme.Tasks.timelineCardRadius, style: .continuous)

        // The time is on the axis (and the due tick), so no time or due text
        // here; one title line keeps the height exact for layout.
        TaskRowContent(
            task: task,
            listName: list?.title,
            tint: list?.color ?? theme.secondaryText,
            isReadOnly: isReadOnly,
            ringPlacement: .firstLine,
            ringSize: AppTheme.Tasks.embeddedRingSize,
            ringHitTarget: AppTheme.Tasks.timelineCardRingHitTarget,
            spacing: AppTheme.Tasks.timelineCardRingToText,
            titleLineLimit: 1,
            onToggle: onComplete
        )
        .padding(.horizontal, AppTheme.Tasks.timelineCardPaddingH)
        .padding(.vertical, TimedTaskCardMetrics.verticalPadding)
        .frame(minWidth: minWidth, alignment: .leading)
        .frame(height: TimedTaskCardMetrics.height(hasSecondLine: Self.hasSecondLine(task, listName: list?.title)), alignment: .top)
        // Opaque underneath, so grid lines never cut through the card.
        .background(shape.fill(fill).background(shape.fill(theme.background)))
        .overlay(shape.strokeBorder(theme.tasks.timelineCardKeyline, lineWidth: 0.5))
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onTapGesture {
            onSelect()
            coordinator.toggleDetail(for: .init(taskID: task.id, day: day))
        }
        .help(task.title)
        .calendarTaskInteractions(task, day: day, coordinator: coordinator, arrowEdge: .trailing, isActive: isActive,
                                  onComplete: isProjected ? {} : onComplete)
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.isCompleted ? L10n.tr("timedtaskmarkerview.completed", "Completed") : L10n.tr("timedtaskmarkerview.not.completed", "Not completed"))
        .accessibilityAction(named: "Complete Task") { if !isReadOnly { onComplete() } }
    }
}
