import SwiftUI
import Domain
import UI

extension EventQuickAddEditorView {
    // MARK: Controls

    var form: QuickAddForm {
        QuickAddForm(focus: focus, openEditor: $openEditor, repeating: $edit.repeating, calendar: calendar,
                     dateFormatter: dateFormatter, name: accessibilityName)
    }

    /// A day in the compact, locale-aware style both dates use.
    func dateControl<Editor: View>(_ field: QuickAddField, day: Date, @ViewBuilder editor: @escaping () -> Editor) -> some View {
        form.control(field, value: form.format(day), placeholder: "", minWidth: QuickAddGrid.shortControlWidth,
                     step: { step(field, $0) }, editor: editor)
    }

    /// Location is typed, on the same surface as the other controls.
    var locationField: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let isFocused = focus.wrappedValue == .location
        return TextField(L10n.tr("eventquickaddeditorview.controls.add.location", "Add location"), text: $edit.location)
            .textFieldStyle(.plain)
            .themedTextInput()
            .foregroundStyle(theme.editor.text)
            .opacity(edit.location.isEmpty ? theme.editor.nativePlaceholderOpacity : 1)
            .focused(focus, equals: .location)
            .padding(.horizontal, 8)
            .frame(width: QuickAddGrid.menuControlWidth * 1.6, height: QuickAddGrid.controlHeight - 2)
            .themedSurface(.control, fill: isFocused ? theme.editor.fieldFocusedFill : theme.editor.fieldFill, in: shape)
            .overlay(shape.strokeBorder(theme.editor.fieldKeyline, lineWidth: 1))
            .overlay {
                if isFocused { shape.strokeBorder(theme.editor.focusRing, lineWidth: 1.5).padding(-1.5) }
            }
            .accessibilityLabel(L10n.tr("eventquickaddeditorview.controls.location", "Location"))
    }

    // MARK: Stepping (closed controls)

    /// ← / → a day or 15 minutes, ↑ / ↓ a week or an hour; Delete makes it
    /// all day (Starts' time).
    func step(_ field: QuickAddField, _ key: KeyEquivalent) -> KeyPress.Result {
        let timing = edit.timing
        switch field {
        case .date, .endDate:
            guard key != .delete else { return .ignored }
            stepDay(field == .date ? \.firstDay : \.lastDay, by: key.step(small: 1, large: 7))
        case .time:
            if key == .delete { edit.timing.isAllDay = true; return .handled }
            guard !timing.isAllDay else { edit.timing.isAllDay = false; return .handled }
            edit.timing.start = timing.start.addingTimeInterval(Self.seconds(key))
        case .endTime:
            guard key != .delete else { return .ignored }
            // A step back that would reach the start is refused, rather than wrapping to the next day.
            let end = timing.end.addingTimeInterval(Self.seconds(key))
            if end > timing.start { edit.timing.end = end }
        default:
            return .ignored
        }
        return .handled
    }

    /// The start or the end day, a number of days on; the timing keeps its rules.
    private func stepDay(_ day: WritableKeyPath<EventTiming, Date>, by days: Int) {
        let current = edit.timing[keyPath: day]
        edit.timing[keyPath: day] = calendar.date(byAdding: .day, value: days, to: current) ?? current
    }

    /// A time's step: 15 minutes, or an hour.
    private static func seconds(_ key: KeyEquivalent) -> TimeInterval {
        TimeInterval(key.step(small: 15, large: 60) * 60)
    }
}
