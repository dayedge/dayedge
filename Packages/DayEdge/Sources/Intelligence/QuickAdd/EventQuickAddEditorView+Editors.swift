import SwiftUI
import Domain
import UI

extension EventQuickAddEditorView {
    // MARK: Editors

    /// One date editor, used for the start and the end.
    func datePopover(_ day: Binding<Date>) -> some View {
        QuickAddPopover(close: form.close) {
            DatePicker(L10n.tr("eventquickaddeditorview.editors.date", "Date"), selection: day, displayedComponents: .date)
                .datePickerStyle(.graphical)
        }
    }

    /// One time editor, used for the start (with "All Day") and the end.
    func timePopover(_ time: Binding<Date>, removeTitle: String? = nil, remove: @escaping () -> Void = {}) -> some View {
        QuickAddPopover(removeTitle: removeTitle, remove: remove, close: form.close) {
            DatePicker(L10n.tr("eventquickaddeditorview.editors.time", "Time"), selection: time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.stepperField)
        }
    }
}
