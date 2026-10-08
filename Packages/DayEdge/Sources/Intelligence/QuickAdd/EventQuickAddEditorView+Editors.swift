import SwiftUI
import Domain
import UI

extension EventQuickAddEditorView {
    // MARK: Editors

    var datePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(L10n.tr("eventquickaddeditorview.editors.date", "Date"), selection: Binding(get: { edit.day }, set: { edit.move(to: $0, calendar: calendar) }),
                       displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.graphical)
            HStack {
                Spacer()
                Button(L10n.tr("eventquickaddeditorview.editors.done", "Done")) { openEditor = nil }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .onKeyPress(.return) { openEditor = nil; return .handled }
    }

    var startPopover: some View {
        timePopover(Binding(get: { edit.start }, set: { edit.setStart($0) }), removeTitle: L10n.tr("eventquickaddeditorview.editors.all.day", "All Day")) {
            edit.isAllDay = true
        }
    }

    var endPopover: some View {
        timePopover(Binding(get: { edit.end }, set: { edit.setEnd(timeOf: $0, calendar: calendar) }), removeTitle: nil) {}
    }

    private func timePopover(_ time: Binding<Date>, removeTitle: String?, remove: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(L10n.tr("eventquickaddeditorview.editors.time", "Time"), selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
            HStack {
                if let removeTitle {
                    Button(removeTitle) {
                        remove()
                        openEditor = nil
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                Spacer()
                Button(L10n.tr("eventquickaddeditorview.editors.done", "Done")) { openEditor = nil }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .onKeyPress(.return) { openEditor = nil; return .handled }
    }
}
