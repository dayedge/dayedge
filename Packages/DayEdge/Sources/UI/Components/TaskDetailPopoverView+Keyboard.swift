import SwiftUI
import Domain

extension TaskDetailPopoverView {
    // MARK: Keyboard (↑ / ↓ select, ↩ opens, Esc closes)

    private var navigation: DetailNavigation {
        guard !isReadOnly else { return DetailNavigation(rows: []) }
        var rows = ["title", "date", "time"]
        if task.dueDate != nil { rows.append("repeat") }
        rows += ["alert", "priority", "url", "notes"]
        return DetailNavigation(rows: rows)
    }

    /// False lets the key through (read-only, nothing selected).
    func handleKey(_ key: DetailKeyboard.Key) -> Bool {
        switch key {
        case .up, .down:
            guard !navigation.rows.isEmpty else { return false }
            selectedRow = navigation.move(from: selectedRow, by: key == .up ? -1 : 1)
        case .activate:
            guard let selectedRow else { return false }
            open(selectedRow)
        case .close:
            dismiss()
        }
        return true
    }

    /// Opens a property's editor (one at a time); the row stays selected.
    func open(_ row: String) {
        selectedRow = row
        switch row {
        case "title": focus = .title
        case "url": urlRequest += 1
        case "notes": notesRequest += 1
        case "time":
            // A draft: nothing is written until Done.
            let day = task.dueDate ?? Date()
            timeDraft = task.hasDueTime ? day : (calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)
            editor = row
        default: editor = row
        }
    }

    func step(from row: String, forward: Bool) {
        selectedRow = navigation.move(from: row, by: forward ? 1 : -1)
    }

    func editorBinding(_ row: String) -> Binding<Bool> {
        Binding(get: { editor == row }, set: { if !$0, editor == row { editor = nil } })
    }
}
