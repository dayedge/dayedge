import SwiftUI
import Domain

/// A task's content, the same wherever a task appears: the completion ring,
/// the title (with its time, where the container shows one), a second line
/// only when it adds something (list · due text · repeat), and `!!` for
/// high priority. Containers — `TaskRowView`'s rows, the Day timeline's
/// card — own padding, surface, hover and tap; this owns what a task *is*.
package struct TaskRowContent: View {
    @Environment(\.themePalette) private var theme

    /// Where the ring sits relative to the text.
    package enum RingPlacement {
        /// The Tasks view: its own ring, nudged onto the title's baseline.
        case plain
        /// Among events: the shared marker column (`AgendaLeadingMarkerSlot`).
        case markerSlot
        /// Inside a surface of its own (Day timeline card): centered on the
        /// title's first line, like a checkbox beside its label.
        case firstLine
    }

    package let task: TaskItem
    package var listName: String?
    package let tint: Color
    package var due: TaskDueText?
    package var timeLabel: String?
    package var isReadOnly = false
    package var density: AgendaRowDensity = .regular
    package var ringPlacement: RingPlacement = .plain
    package var ringSize: CGFloat = AppTheme.Tasks.ringSize
    /// The ring's click area: a fixed square around it.
    package var ringHitTarget: CGFloat = AppTheme.AgendaRow.ringHitTarget
    package var spacing: CGFloat = 10
    package var titleLineLimit = 2
    /// Compact rows in search: a fixed time column, so titles line up with
    /// events' (nil: as long as the time is).
    package var compactTimeColumnWidth: CGFloat?
    /// Search: a long compact title fades out at the edge instead of "…".
    package var compactTitleFades = false
    package let onToggle: () -> Void

    @State private var isHoveringRing = false

    package var hasSecondLine: Bool { Self.hasSecondLine(listName: listName, due: due, task: task) }

    package static func hasSecondLine(listName: String?, due: TaskDueText?, task: TaskItem) -> Bool {
        listName != nil || due != nil || task.isRecurring
    }

    package var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            switch ringPlacement {
            case .plain:
                completionRing.padding(.top, 1)
            case .markerSlot:
                AgendaLeadingMarkerSlot { completionRing }
            case .firstLine:
                completionRing
                    .alignmentGuide(.top) { d in d[VerticalAlignment.center] - AppTheme.AgendaRow.firstLineCenter }
            }

            VStack(alignment: .leading, spacing: 2) {
                switch density {
                case .regular:
                    if let timeLabel { timeText(timeLabel) }
                    titleText
                        .lineLimit(titleLineLimit)
                        .fixedSize(horizontal: false, vertical: titleLineLimit > 1)
                case .compact:
                    // A reference: time and title on one line.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let compactTimeColumnWidth {
                            timeText(timeLabel ?? " ")
                                .lineLimit(1)
                                .frame(width: compactTimeColumnWidth, alignment: .leading)
                        } else if let timeLabel {
                            timeText(timeLabel)
                        }
                        if compactTitleFades {
                            titleText.fadingOverflow()
                        } else {
                            titleText
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }

                if hasSecondLine { secondLine }
            }
            .layoutPriority(-1) // truncate the text, never the priority mark

            Spacer(minLength: 8)

            if task.priority == .high && !task.isCompleted {
                Text("!!")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.content.ongoingIndicator)
                    .padding(.top, 1)
            }
        }
    }

    private func timeText(_ label: String) -> some View {
        Text(label)
            .font(AppTheme.TextStyle.eventTime)
            .foregroundStyle(theme.secondaryText)
    }

    private var titleText: some View {
        Text(verbatim: task.title)
            .font(AppTheme.TextStyle.eventTitle)
            .foregroundStyle(task.isCompleted ? theme.secondaryText : theme.primaryText)
            .strikethrough(task.isCompleted)
    }

    /// The completion control. Its click area is a fixed square around the
    /// ring, never the whole row; hover and selection don't move it.
    private var completionRing: some View {
        TaskCheckbox(color: task.isCompleted ? tint.opacity(theme.sourcePresentation.completedTaskOpacity) : tint, isCompleted: task.isCompleted,
                     isHovering: isHoveringRing, size: ringSize)
            .opacity(isReadOnly ? theme.sourcePresentation.readOnlyTaskOpacity : 1)
            .contentShape(Rectangle().inset(by: -max((ringHitTarget - ringSize) / 2, 0)))
            .onHover { isHoveringRing = $0 && !isReadOnly }
            .onTapGesture { if !isReadOnly { onToggle() } }
            .accessibilityLabel(task.isCompleted ? L10n.tr(
                "taskrowcontent.mark.as.not.completed", "Mark as Not Completed"
            ) : L10n.tr(
                "taskrowcontent.complete.task", "Complete Task"
            ))
    }

    private var secondLine: some View {
        HStack(spacing: 4) {
            if let listName {
                Text(listName)
                    .foregroundStyle(theme.secondaryText)
            }
            if listName != nil && due != nil {
                Text("·").foregroundStyle(theme.content.quietMetadata)
            }
            if let due {
                Text(due.text)
                    .foregroundStyle(due.isOverdue && !task.isCompleted ? theme.tasks.attentionTint : theme.secondaryText)
            }
            if task.isRecurring {
                Image(systemName: "repeat")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.content.subduedMetadata)
            }
        }
        .font(AppTheme.TextStyle.eventSubtitle)
        .lineLimit(1)
    }

    package init(
        task: TaskItem,
        listName: String? = nil,
        tint: Color,
        due: TaskDueText? = nil,
        timeLabel: String? = nil,
        isReadOnly: Bool = false,
        density: AgendaRowDensity = .regular,
        ringPlacement: RingPlacement = .plain,
        ringSize: CGFloat = AppTheme.Tasks.ringSize,
        ringHitTarget: CGFloat = AppTheme.AgendaRow.ringHitTarget,
        spacing: CGFloat = 10,
        titleLineLimit: Int = 2,
        compactTimeColumnWidth: CGFloat? = nil,
        compactTitleFades: Bool = false,
        onToggle: @escaping () -> Void
    ) {
        self.task = task
        self.listName = listName
        self.tint = tint
        self.due = due
        self.timeLabel = timeLabel
        self.isReadOnly = isReadOnly
        self.density = density
        self.ringPlacement = ringPlacement
        self.ringSize = ringSize
        self.ringHitTarget = ringHitTarget
        self.spacing = spacing
        self.titleLineLimit = titleLineLimit
        self.compactTimeColumnWidth = compactTimeColumnWidth
        self.compactTitleFades = compactTitleFades
        self.onToggle = onToggle
    }
}
