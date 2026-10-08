import SwiftUI
import Domain

extension TaskDetailPopoverView {
    // MARK: Repeat, alert, priority

    /// The shared Repeat editor, read from the due date; Custom… morphs it.
    var repeatRow: some View {
        DetailEditorRow(
            icon: "repeat", text: task.recurrence.title, isPlaceholder: !task.isRecurring,
            isEditing: editor == "repeat", isKeyboardSelected: selectedRow == "repeat",
            onClear: task.isRecurring ? { onEdit(.recurrenceRule(nil)) } : nil
        ) { open("repeat") }
        .propertyEditor(isPresented: editorBinding("repeat")) {
            RepeatEditor(current: task.effectiveRecurrenceRule, anchor: task.dueDate ?? Date()) { rule in
                editor = nil
                if rule != task.effectiveRecurrenceRule { onEdit(.recurrenceRule(rule)) }
            }
        }
    }

    private var alertText: String {
        switch task.alert {
        case nil: return L10n.tr("taskdetailpopoverview.rows.add.alert", "Add alert")
        case .relative(let minutes)?:
            return minutes == 0 ? L10n.tr("taskdetailpopoverview.rows.at.due.time", "At due time") : TaskAlert.relative(minutesBefore: minutes).title(format: timeFormat)
        case .absolute(let date)?:
            return dateFormatter.format(date, .compact, weekday: .abbreviated) + " " + timeFormat.time(date)
        }
    }

    /// None, the presets (with a due time), or a specific time — which
    /// morphs the same editor into a date and time page.
    var alertRow: some View {
        var items = [ChoiceItem(id: "none", title: L10n.tr("taskdetailpopoverview.rows.none", "None"), isChecked: task.alert == nil)]
        if task.dueDate != nil && task.hasDueTime {
            items.append(.separator("after-none"))
            items += TaskAlert.relativePresets.map { minutes in
                let alert = TaskAlert.relative(minutesBefore: minutes)
                return ChoiceItem(id: "m\(minutes)", title: minutes == 0 ? L10n.tr(
                    "taskdetailpopoverview.rows.at.due.time", "At due time"
                ) : alert.title(format: timeFormat), isChecked: task.alert == alert)
            }
        }
        let specificStart: Date = {
            if case .absolute(let date)? = task.alert { return date }
            return task.dueDate ?? Date().addingTimeInterval(3600)
        }()
        return DetailEditorRow(
            icon: "bell", text: alertText, isPlaceholder: task.alert == nil,
            isEditing: editor == "alert", isKeyboardSelected: selectedRow == "alert",
            onClear: task.alert == nil ? nil : { onEdit(.alert(nil)) }
        ) { open("alert") }
        .propertyEditor(isPresented: editorBinding("alert")) {
            AlertEditor(items: items, specificStart: specificStart, onChoose: { item in
                editor = nil
                if item.id == "none" {
                    onEdit(.alert(nil))
                } else if let minutes = Int(item.id.dropFirst()) {
                    onEdit(.alert(.relative(minutesBefore: minutes)))
                }
            }, onSpecific: { date in
                editor = nil
                onEdit(.alert(.absolute(date)))
            })
        }
    }

    var priorityRow: some View {
        DetailEditorRow(
            icon: "exclamationmark.2",
            text: task.priority == .none ? L10n.tr("taskdetailpopoverview.rows.add.priority", "Add priority") : task.priority.title,
            isPlaceholder: task.priority == .none,
            isEditing: editor == "priority", isKeyboardSelected: selectedRow == "priority",
            onClear: task.priority == .none ? nil : { onEdit(.priority(.none)) }
        ) { open("priority") }
        .propertyEditor(isPresented: editorBinding("priority")) {
            PropertyEditor(width: .compact) {
                ChoiceListEditor(items: TaskPriority.allCases.map {
                    ChoiceItem(id: "\($0.rawValue)", title: $0.title, isChecked: $0 == task.priority)
                }) { item in
                    editor = nil
                    if let raw = Int(item.id), let priority = TaskPriority(rawValue: raw), priority != task.priority {
                        onEdit(.priority(priority))
                    }
                }
            }
        }
    }

    // MARK: URL (inline)

    var urlRow: some View {
        DetailInlineTextRow(
            icon: "link", value: task.url?.absoluteString, placeholder: L10n.tr("taskdetailpopoverview.rows.add.url", "Add URL"), prompt: "https://",
            display: { URL(string: $0).map(Self.displayURL) ?? $0 },
            isKeyboardSelected: selectedRow == "url", editRequest: urlRequest,
            onTab: { step(from: "url", forward: $0) },
            onCommit: { text in
                // Valid links save; an invalid one is dropped and the row reverts.
                if text.isEmpty { return onEdit(.url(nil)) }
                let candidate = text.contains("://") ? text : "https://" + text
                if let url = URL(string: candidate), url.host() != nil, url != task.url { onEdit(.url(url)) }
            }
        )
    }

    private static func displayURL(_ url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        let path = url.path(percentEncoded: false)
        return path.isEmpty || path == "/" ? host : host + path
    }

    // MARK: Commits

    func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            titleDraft = task.title // an empty title isn't allowed: revert
        } else if trimmed != task.title {
            onEdit(.title(trimmed))
        }
    }

    package init(
        task: TaskItem,
        lists: [CalendarSource],
        onEdit: @escaping (TaskChange) -> Void,
        onToggleCompleted: @escaping () -> Void,
        isReadOnly: Bool = false
    ) {
        self.task = task
        self.lists = lists
        self.onEdit = onEdit
        self.onToggleCompleted = onToggleCompleted
        self.isReadOnly = isReadOnly
    }
}
