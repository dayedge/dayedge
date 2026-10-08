import SwiftUI
import Domain

/// Task Details — the sibling of `EventDetailPopoverView`, composed of the
/// same pieces: identity block with the shared list selector, the shared
/// row geometry and hover, one property editor shell (`PropertyEditor`),
/// choice editors that can morph (Repeat → Custom…, Alert → At a Specific
/// Time…), inline text. Presentation first: a property becomes an editor
/// only when opened — by a click, or ↑ / ↓ and ↩. One editor at a time;
/// the row stays selected after it closes. Compound editors edit a draft
/// saved by Done (↩) and dropped by Cancel (Esc). Reversible changes save
/// with Undo, as everywhere in the app.
package struct TaskDetailPopoverView: View {
    @Environment(\.themePalette) var theme
    @Environment(\.timeFormat) var timeFormat
    @Environment(\.dateFormatter) var dateFormatter

    package let task: TaskItem
    package let lists: [CalendarSource]
    package let onEdit: (TaskChange) -> Void
    package let onToggleCompleted: () -> Void
    /// The task's list can't be edited: show everything, change nothing.
    package var isReadOnly = false

    enum Field: Hashable { case title }

    @Environment(\.dismiss) var dismiss
    @Environment(\.openAppSettings) private var openSettings
    /// The one property editor open ("date", "time", "repeat", "alert", "priority").
    @State var editor: String?
    /// The keyboard's row (↑ / ↓); editors return to it when they close.
    @State var selectedRow: String?
    @State var titleDraft = ""
    /// The time editor's draft.
    @State var timeDraft = Date()
    @State var urlRequest = 0
    @State var notesRequest = 0
    @FocusState var focus: Field?

    var calendar: Calendar { .autoupdatingCurrent }
    private var list: CalendarSource? { lists.first { $0.id == task.listID } }
    private var tint: Color { list?.color ?? theme.secondaryText }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: DetailMetrics.rowSpacing) {
                dateRow
                timeRow
                if task.dueDate != nil { repeatRow }
                alertRow
                priorityRow
                urlRow
            }
            .padding(.top, DetailMetrics.identityToRows)
            DetailDivider()
            DetailNotesSection(notes: task.notes, isKeyboardSelected: selectedRow == "notes",
                               editRequest: notesRequest) { onEdit(.notes($0)) }
        }
        .detailSurface()
        .disabled(isReadOnly)
        .onAppear { titleDraft = task.title }
        .onDisappear(perform: commitTitle)
        .onChange(of: task.title) { _, new in if focus != .title { titleDraft = new } }
        .onChange(of: focus) { old, _ in
            if old == .title { commitTitle() }
        }
        .detailKeyboard(handleKey)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggleCompleted) {
                TaskCheckbox(color: tint, isCompleted: task.isCompleted)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(task.isCompleted ? L10n.tr(
                "taskdetailpopoverview.mark.as.not.completed", "Mark as not completed"
            ) : L10n.tr(
                "taskdetailpopoverview.mark.as.completed", "Mark as completed"
            ))

            // A plain field reads as the title itself until focused.
            TextField(L10n.tr("taskdetailpopoverview.title", "Title"), text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(task.isCompleted ? theme.secondaryText : theme.primaryText)
                .strikethrough(task.isCompleted)
                .lineLimit(1...4)
                .focused($focus, equals: .title)
                .onSubmit(commitTitle)
                .onExitCommand {
                    titleDraft = task.title
                    focus = nil
                }
                .onKeyPress(.tab, phases: .down) { press in
                    focus = nil
                    step(from: "title", forward: !press.modifiers.contains(.shift))
                    return .handled
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            listSelector
                .padding(.top, 1)
        }
    }

    /// The task's list, as part of its identity — the same selector events
    /// use for their calendar, grouped by account.
    private var listSelector: some View {
        CollectionSelector(
            current: CollectionOption(id: task.listID, title: list?.title ?? L10n.tr("taskdetailpopoverview.no.list", "No List"), color: tint),
            options: isReadOnly ? [] : lists.filter(\.allowsModifications).map {
                CollectionOption(id: $0.id, title: $0.title, color: $0.color, group: $0.sourceTitle)
            },
            manageTitle: L10n.tr("taskdetailpopoverview.manage.lists", "Manage Lists…"),
            onManage: openSettings.map { open in { open(.tasks) } }
        ) { id in if id != task.listID { onEdit(.list(id)) } }
    }
}
