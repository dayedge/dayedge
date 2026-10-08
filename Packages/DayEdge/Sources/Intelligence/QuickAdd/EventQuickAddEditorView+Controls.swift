import SwiftUI
import Domain
import UI

extension EventQuickAddEditorView {
    // MARK: Controls

    func choiceControl<Value: Hashable>(_ field: QuickAddField, value: String, options: [(Value, String)],
                                        selection: Value, choose: @escaping (Value) -> Void) -> some View {
        control(field, value: value, placeholder: "", hasMenu: true, minWidth: QuickAddGrid.menuControlWidth) {
            QuickAddChoiceList(options: options, selection: selection) { value in
                choose(value)
                openEditor = nil
            }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard let index = options.firstIndex(where: { $0.0 == selection }) else { return .ignored }
            let step = press.key == .rightArrow ? 1 : -1
            choose(options[(index + step + options.count) % options.count].0)
            return .handled
        }
    }

    func control<Editor: View>(_ field: QuickAddField, value: String?, placeholder: String, hasMenu: Bool = false,
                               minWidth: CGFloat, @ViewBuilder editor: @escaping () -> Editor) -> some View {
        QuickAddControl(
            text: value ?? placeholder,
            isPlaceholder: value == nil,
            hasMenu: hasMenu,
            isFocused: focus.wrappedValue == field,
            minWidth: minWidth
        )
        .quickAddControl(field, focus: focus) { open(field) }
        .onKeyPress(keys: [.date, .time, .endTime].contains(field) ? [.leftArrow, .rightArrow, .upArrow, .downArrow, .delete] : []) { press in
            step(field, press.key)
        }
        .popover(isPresented: Binding(get: { openEditor == field }, set: { if !$0, openEditor == field { openEditor = nil } }),
                 arrowEdge: .bottom) {
            editor()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName(field))
        .accessibilityValue(value ?? placeholder)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(field) }
    }

    /// Location is typed, on the same surface as the other controls.
    var locationField: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let isFocused = focus.wrappedValue == .location
        return TextField(L10n.tr("eventquickaddeditorview.controls.add.location", "Add location"), text: $edit.location)
            .textFieldStyle(.plain)
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

    private func open(_ field: QuickAddField) {
        focus.wrappedValue = field
        if field == .time, edit.isAllDay { edit.isAllDay = false }
        openEditor = field
    }

    // MARK: Stepping (closed controls)

    /// ← / → a day or 15 minutes, ↑ / ↓ a week or an hour; Delete makes it
    /// all day (Starts).
    private func step(_ field: QuickAddField, _ key: KeyEquivalent) -> KeyPress.Result {
        switch field {
        case .date:
            guard key != .delete else { return .ignored }
            let days = key == .leftArrow ? -1 : key == .rightArrow ? 1 : key == .upArrow ? -7 : 7
            edit.move(to: calendar.date(byAdding: .day, value: days, to: edit.day) ?? edit.day, calendar: calendar)
        case .time:
            if key == .delete { edit.isAllDay = true; return .handled }
            guard !edit.isAllDay else { edit.isAllDay = false; return .handled }
            edit.setStart(edit.start.addingTimeInterval(Self.minutes(key) * 60))
        case .endTime:
            guard key != .delete else { return .ignored }
            let end = edit.end.addingTimeInterval(Self.minutes(key) * 60)
            if end > edit.start { edit.end = end }
        default:
            return .ignored
        }
        return .handled
    }

    private static func minutes(_ key: KeyEquivalent) -> Double {
        key == .leftArrow ? -15 : key == .rightArrow ? 15 : key == .upArrow ? -60 : 60
    }
}
