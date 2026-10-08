import SwiftUI
import Domain

/// One reminder row: `TaskRowContent` (ring, title, a second line only when
/// it adds something) in a row container — visually a sibling of
/// `AgendaEventRowView`, same inset highlight and paddings.
package struct TaskRowView: View {
    @Environment(\.themePalette) private var theme

    package enum Style {
        /// The Tasks view: its own layout and ring, unchanged.
        case regular
        /// Among events (agenda, day view): the shared marker/content grid,
        /// a slightly larger ring with a bigger click area.
        case embedded
    }

    package let task: TaskItem
    package var listName: String?
    package let tint: Color
    package var due: TaskDueText?
    /// Calendar views: a timed task's time, above the title like an
    /// event's time line (the task still has no duration).
    package var timeLabel: String?
    package let isSelected: Bool
    package let isDetailPresented: Bool
    /// In a list that can't be edited: the checkbox is inert and dimmed.
    package var isReadOnly = false
    package var style: Style = .regular
    /// Just created (Quick Add): settles in with a brief emphasis.
    package var isArriving = false
    /// `.compact` in chat: time and title on one line, tighter.
    package var density: AgendaRowDensity = .regular
    /// Off where a container draws the selection (search results).
    package var drawsSelectionBackground = true
    package var compactTimeColumnWidth: CGFloat?
    package var compactTitleFades = false
    package let onToggle: () -> Void
    package let onTap: () -> Void

    @State private var isHovering = false
    @State private var lastDismissAt: Date = .distantPast

    private var rowBackground: Color {
        if isDetailPresented { return theme.content.detailSelectionFill }
        if isSelected { return theme.chrome.rowSelection }
        if isHovering { return theme.chrome.rowHover }
        return .clear
    }

    package var body: some View {
        TaskRowContent(
            task: task, listName: listName, tint: tint, due: due, timeLabel: timeLabel,
            isReadOnly: isReadOnly, density: density,
            ringPlacement: style == .embedded ? .markerSlot : .plain,
            ringSize: style == .embedded ? AppTheme.Tasks.embeddedRingSize : AppTheme.Tasks.ringSize,
            spacing: style == .embedded ? AppTheme.AgendaRow.markerToContent : 10,
            compactTimeColumnWidth: compactTimeColumnWidth,
            compactTitleFades: compactTitleFades,
            onToggle: onToggle
        )
        .padding(.leading, style == .embedded ? AppTheme.AgendaRow.leadingInset : AppTheme.horizontalPadding)
        .padding(.trailing, AppTheme.horizontalPadding)
        .padding(.vertical, density.verticalPadding)
        .background(
            ThemedSurface(role: isSelected ? .selection : .hover,
                            fill: drawsSelectionBackground ? rowBackground : .clear,
                            shape: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onChange(of: isDetailPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented { lastDismissAt = Date() }
        }
        .onTapGesture {
            // Same guard as event rows: ignore the click that just closed
            // the popover, so "second click closes" doesn't reopen it.
            guard isDetailPresented || Date().timeIntervalSince(lastDismissAt) > 0.3 else { return }
            onTap()
        }
        .modifier(ArrivalEmphasis(isActive: isArriving))
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.isCompleted ? L10n.tr("taskrowview.completed", "Completed") : L10n.tr("taskrowview.not.completed", "Not completed"))
        .accessibilityAction(named: task.isCompleted ? L10n.tr(
            "taskrowview.mark.as.not.completed", "Mark as Not Completed"
        ) : L10n.tr(
            "taskrowview.complete.task", "Complete Task"
        )) {
            if !isReadOnly { onToggle() }
        }
    }

    package init(
        task: TaskItem,
        listName: String? = nil,
        tint: Color,
        due: TaskDueText? = nil,
        timeLabel: String? = nil,
        isSelected: Bool,
        isDetailPresented: Bool,
        isReadOnly: Bool = false,
        style: Style = .regular,
        isArriving: Bool = false,
        density: AgendaRowDensity = .regular,
        drawsSelectionBackground: Bool = true,
        compactTimeColumnWidth: CGFloat? = nil,
        compactTitleFades: Bool = false,
        onToggle: @escaping () -> Void,
        onTap: @escaping () -> Void
    ) {
        self.task = task
        self.listName = listName
        self.tint = tint
        self.due = due
        self.timeLabel = timeLabel
        self.isSelected = isSelected
        self.isDetailPresented = isDetailPresented
        self.isReadOnly = isReadOnly
        self.style = style
        self.isArriving = isArriving
        self.density = density
        self.drawsSelectionBackground = drawsSelectionBackground
        self.compactTimeColumnWidth = compactTimeColumnWidth
        self.compactTitleFades = compactTitleFades
        self.onToggle = onToggle
        self.onTap = onTap
    }
}

/// A newly created task's arrival: it fades up from 60% and settles from a
/// hair smaller, once — no color, no glow. Reduce Motion: fade only.
private struct ArrivalEmphasis: ViewModifier {
    let isActive: Bool
    @State private var hasArrived = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(hasArrived ? 1 : 0.6)
            .scaleEffect(hasArrived || reduceMotion ? 1 : 0.985)
            .onChange(of: isActive, initial: true) { _, active in
                guard active else { return }
                hasArrived = false
                withAnimation(.easeOut(duration: 0.24).delay(0.05)) { hasArrived = true }
            }
    }
}
