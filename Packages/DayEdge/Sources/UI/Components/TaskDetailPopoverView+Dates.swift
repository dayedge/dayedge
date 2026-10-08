import SwiftUI
import Domain

extension TaskDetailPopoverView {
    // MARK: Date & time

    private var dateText: String? {
        guard let due = task.dueDate else { return nil }
        let dates = dateFormatter.with(calendar)
        return dates.relativeDay(due) ?? dates.format(due, .standard)
    }

    private var isOverdue: Bool {
        TaskBuckets.isOverdue(task, now: Date(), calendar: calendar) && !task.isCompleted
    }

    var dateRow: some View {
        DetailEditorRow(
            icon: "calendar",
            text: dateText ?? L10n.tr("taskdetailpopoverview.dates.add.date", "Add date"),
            isPlaceholder: task.dueDate == nil,
            tint: isOverdue ? theme.tasks.attentionTint : nil,
            isEditing: editor == "date",
            isKeyboardSelected: selectedRow == "date",
            onClear: task.dueDate == nil ? nil : { onEdit(.due(nil, hasTime: false)) }
        ) { open("date") }
        .propertyEditor(isPresented: editorBinding("date")) {
            // Picking a day applies it (one click, like a menu choice).
            PropertyEditor(width: .fit) {
                PropertyEditorCalendar(selection: Binding(
                    get: { task.dueDate ?? Date() },
                    set: { newDay in
                        // One click can be reported twice: apply the first only.
                        guard editor == "date" else { return }
                        editor = nil
                        onEdit(.due(merge(day: newDay), hasTime: task.hasDueTime))
                    }
                ))
            }
        }
    }

    var timeRow: some View {
        DetailEditorRow(
            icon: AppTheme.Symbol.time,
            text: task.hasDueTime ? (task.dueDate.map { timeFormat.time($0) } ?? "") : L10n.tr("taskdetailpopoverview.dates.add.time", "Add time"),
            isPlaceholder: !task.hasDueTime,
            isEditing: editor == "time",
            isKeyboardSelected: selectedRow == "time",
            onClear: task.hasDueTime ? { removeTime() } : nil
        ) { open("time") }
        .propertyEditor(isPresented: editorBinding("time")) {
            PropertyEditor(width: .compact, onCancel: { editor = nil }, onDone: {
                onEdit(.due(timeDraft, hasTime: true))
                editor = nil
            }, content: {
                PropertyEditorField(label: "Due at") {
                    DatePicker(L10n.tr("taskdetailpopoverview.dates.due.at", "Due at"), selection: $timeDraft, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
            })
        }
    }

    private func removeTime() {
        guard let due = task.dueDate else { return }
        onEdit(.due(calendar.startOfDay(for: due), hasTime: false))
    }

    /// Picking a new day keeps the existing clock time.
    private func merge(day: Date) -> Date {
        guard task.hasDueTime, let due = task.dueDate else { return calendar.startOfDay(for: day) }
        let time = calendar.dateComponents([.hour, .minute], from: due)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}
