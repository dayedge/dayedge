import AppKit
import SwiftUI
import Domain

extension EventDetailPopoverView {
    // MARK: Editing (own events without attendees)

    @ViewBuilder
    var editableRows: some View {
        DetailEditorRow(icon: "calendar", text: dateFormatter.format(date, .standard),
                        isEditing: editor == "date", isKeyboardSelected: selectedRow == "date") { open("date") }
            .propertyEditor(isPresented: editorBinding("date")) {
                PropertyEditor(width: .fit) {
                    PropertyEditorCalendar(selection: Binding(get: { date }, set: { moveTo(day: $0) }))
                }
            }

        if let start = event.startDate, let end = event.endDate {
            DetailEditorRow(icon: AppTheme.Symbol.time, text: event.isAllDay ? L10n.tr("eventdetailpopoverview.editing.all.day", "All day") : (timeText ?? ""),
                            isEditing: editor == "time", isKeyboardSelected: selectedRow == "time") { open("time") }
                .propertyEditor(isPresented: editorBinding("time")) {
                    EventTimeEditor(start: start, end: end, isAllDay: event.isAllDay) { apply($0) }
                }
        }

        repeatRow
        alertRow

        DetailInlineTextRow(icon: "location", value: event.subtitle, placeholder: L10n.tr("eventdetailpopoverview.editing.add.location", "Add location"),
                            isKeyboardSelected: selectedRow == "location", editRequest: locationRequest,
                            onTab: { step(from: "location", forward: $0) }, onCommit: {
            apply(EventChange(location: $0))
        })
    }
}
