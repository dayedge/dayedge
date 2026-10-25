import SwiftUI
import Domain
import UI

/// End Repeat's editor, for tasks and events: the last day on a calendar that starts at the first day, and Never.
struct RepeatEndPopover: View {
    @Binding var lastDay: Date?
    let firstDay: Date
    let calendar: Calendar
    let close: () -> Void

    /// The row's label and the value when there is no end; one wording for both editors.
    static var title: String { L10n.tr("repeatendpopover.end.repeat", "End Repeat") }
    static var never: String { L10n.tr("repeatendpopover.never", "Never") }

    var body: some View {
        let first = calendar.startOfDay(for: firstDay)
        QuickAddPopover(removeTitle: Self.never, remove: { lastDay = nil }, close: close, picker: {
            DatePicker(Self.title, selection: Binding(get: { lastDay ?? first }, set: { lastDay = calendar.startOfDay(for: $0) }),
                       in: first..., displayedComponents: .date)
                .datePickerStyle(.graphical)
        })
    }
}

extension RepeatEdit {
    /// End Repeat's keys on its closed control: ← / → a day, ↑ / ↓ a week, Delete for Never.
    mutating func handle(_ key: KeyEquivalent, firstDay: Date, calendar: Calendar) -> KeyPress.Result {
        if key == .delete {
            lastDay = nil
        } else if lastDay == nil {
            startEnd(firstDay: firstDay, calendar: calendar)
        } else {
            stepEnd(days: key.step(small: 1, large: 7), firstDay: firstDay, calendar: calendar)
        }
        return .handled
    }
}
