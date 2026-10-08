import AppKit
import SwiftUI
import Domain

extension EventDetailPopoverView {
    // MARK: Keyboard (↑ / ↓ select, ↩ opens, Esc closes)

    /// The card's editable properties, top to bottom.
    private var navigation: DetailNavigation {
        if canEdit {
            var rows = ["title", "date"]
            if event.startDate != nil { rows.append("time") }
            rows += ["repeat", "alert", "location", "notes"]
            return DetailNavigation(rows: rows)
        }
        return DetailNavigation(rows: editability.canEditAlerts ? ["alert"] : [])
    }

    /// False lets the key through (no editable rows, nothing selected).
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

    /// Opens a property's editor (one at a time); the row stays selected,
    /// so the keyboard carries on from it when the editor closes.
    func open(_ row: String) {
        selectedRow = row
        switch row {
        case "title": isTitleFocused = true
        case "location": locationRequest += 1
        case "notes": notesRequest += 1
        default: editor = row
        }
    }

    /// Tab / ⇧Tab out of an inline field: select the neighbouring row.
    func step(from row: String, forward: Bool) {
        selectedRow = navigation.move(from: row, by: forward ? 1 : -1)
    }

    func editorBinding(_ row: String) -> Binding<Bool> {
        Binding(get: { editor == row }, set: { if !$0, editor == row { editor = nil } })
    }
}
