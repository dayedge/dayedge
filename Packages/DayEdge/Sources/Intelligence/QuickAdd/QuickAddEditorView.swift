import SwiftUI
import Domain
import UI

/// The Quick Add fields, in keyboard order. A task's Time and Repeat only
/// exist once there is a date; an event's start is `date` and `time`, its end
/// `endDate` and `endTime` (no end time all day); End Repeat only while it repeats. Alert is the event's.
package enum QuickAddField: Hashable, CaseIterable {
    case title, list, date, time, priority, recurrence, repeatEnd
    case calendar, endDate, endTime, location, alert

    package static func order(hasDate: Bool, repeats: Bool) -> [QuickAddField] {
        hasDate ? [.title, .list, .date, .time, .priority, .recurrence] + (repeats ? [.repeatEnd] : [])
            : [.title, .list, .date, .priority]
    }

    package static func eventOrder(isAllDay: Bool, repeats: Bool) -> [QuickAddField] {
        (isAllDay ? [.title, .calendar, .date, .time, .endDate, .location, .recurrence]
            : [.title, .calendar, .date, .time, .endDate, .endTime, .location, .recurrence]) + (repeats ? [.repeatEnd] : []) + [.alert]
    }

    /// Tab / Shift-Tab, wrapping around.
    package static func next(after field: QuickAddField?, in order: [QuickAddField], backward: Bool) -> QuickAddField {
        guard let field, let index = order.firstIndex(of: field) else { return backward ? order[order.count - 1] : order[0] }
        let step = backward ? -1 : 1
        return order[(index + step + order.count) % order.count]
    }
}

/// Create Task, expanded in place: a focused task object with editable
/// properties — native-looking controls, not a settings form. A header
/// (ring + title) over a strict two-column grid: labels share one x,
/// controls share another (leading edges aligned; widths follow content).
///
/// Keyboard (focus order is explicit — the palette's key monitor walks it):
///   Tab / Shift-Tab   next / previous field, wrapping
///   Space / Return    open the focused control's editor
///   ← / →             step the focused value (list, day, 15 min, priority, repeat)
///   ⌘Return           create, from any field (an open editor closes first)
///   Esc               close an open editor, else collapse Quick Add
/// Every editor is a small popover that owns ↑ / ↓, Return and Esc, and
/// hands focus back to its control when it closes.
package struct QuickAddEditorView: View {
    @Environment(\.timeFormat) private var timeFormat
    @Environment(\.dateFormatter) private var dateFormatter
    @Environment(\.themePalette) private var theme

    @Binding package var edit: QuickAddEdit
    package let lists: [CalendarSource]
    package var focus: FocusState<QuickAddField?>.Binding
    @Binding package var openEditor: QuickAddField?
    package let iconColumn: CGFloat
    package let iconToText: CGFloat

    private var calendar: Calendar { .autoupdatingCurrent }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, QuickAddGrid.headerGap)

            VStack(alignment: .leading, spacing: QuickAddGrid.rowSpacing) {
                QuickAddRow(L10n.tr("quickaddeditorview.list", "List")) {
                    form.choice(.list, value: listTitle, options: listOptions, selection: edit.listID) { edit.listID = $0 }
                }
                QuickAddRow(L10n.tr("quickaddeditorview.date", "Date")) {
                    form.control(.date, value: edit.day.map(form.format), placeholder: L10n.tr("quickaddeditorview.add.date", "Add date"),
                                 minWidth: QuickAddGrid.shortControlWidth, step: stepDate,
                                 prepare: { if edit.day == nil { edit.day = calendar.startOfDay(for: Date()) } },
                                 editor: { datePopover })
                }
                if edit.day != nil {
                    QuickAddRow(L10n.tr("quickaddeditorview.time", "Time")) {
                        form.control(.time, value: edit.hasTime ? timeFormat.time(edit.time) : nil,
                                     placeholder: L10n.tr("quickaddeditorview.add.time", "Add time"), minWidth: QuickAddGrid.shortControlWidth,
                                     step: stepTime, prepare: { edit.hasTime = true }, editor: { timePopover })
                    }
                }
                QuickAddRow(L10n.tr("quickaddeditorview.priority", "Priority")) {
                    form.choice(.priority, value: edit.priority.title,
                                options: TaskPriority.allCases.map { ($0, $0.title) }, selection: edit.priority) { edit.priority = $0 }
                }
                if let day = edit.day {
                    QuickAddRow(L10n.tr("quickaddeditorview.repeat", "Repeat")) { form.repeatChoice }
                    form.repeatEndRow(firstDay: day)
                }
            }
            .padding(.leading, iconColumn + iconToText)
        }
        .font(.system(size: 12))
        // Whatever editor closes, focus returns to the control that opened it.
        .onChange(of: openEditor) { previous, current in
            if current == nil, let previous { focus.wrappedValue = previous }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: iconToText) {
            TaskCheckbox(color: listColor, isCompleted: false, size: 13)
                .allowsHitTesting(false)
                .frame(width: iconColumn)
            // The task's name, not a boxed field: no text-field chrome.
            TextField(L10n.tr("quickaddeditorview.title", "Title"), text: $edit.title)
                .textFieldStyle(.plain)
                .themedTextInput()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.editor.titleText)
                .opacity(edit.title.isEmpty ? theme.editor.nativePlaceholderOpacity : 1)
                .focused(focus, equals: .title)
                .accessibilityLabel(L10n.tr("quickaddeditorview.title", "Title"))
        }
    }

    // MARK: Controls

    private var form: QuickAddForm {
        QuickAddForm(focus: focus, openEditor: $openEditor, repeating: $edit.repeating, calendar: calendar,
                     dateFormatter: dateFormatter, name: label(for:))
    }

    // MARK: Editors

    private var datePopover: some View {
        QuickAddPopover(removeTitle: L10n.tr("quickaddeditorview.remove.date", "Remove Date"), remove: {
            edit.day = nil
            edit.hasTime = false
            edit.repeating.recurrence = .never
        }, close: form.close, picker: {
            DatePicker(L10n.tr("quickaddeditorview.date", "Date"), selection: Binding(
                get: { edit.day ?? calendar.startOfDay(for: Date()) },
                set: { edit.day = calendar.startOfDay(for: $0) }
            ), displayedComponents: .date)
                .datePickerStyle(.graphical)
        })
    }

    private var timePopover: some View {
        QuickAddPopover(removeTitle: L10n.tr("quickaddeditorview.remove.time", "Remove Time"), remove: { edit.hasTime = false },
                        close: form.close, picker: {
            DatePicker(L10n.tr("quickaddeditorview.time", "Time"), selection: $edit.time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.stepperField)
        })
    }

    // MARK: Stepping (closed controls)

    private func stepDate(_ key: KeyEquivalent) -> KeyPress.Result {
        if key == .delete { edit.day = nil; edit.hasTime = false; edit.repeating.recurrence = .never; return .handled }
        let days = key.step(small: 1, large: 7)
        let base = edit.day ?? calendar.startOfDay(for: Date())
        edit.day = edit.day == nil ? base : calendar.date(byAdding: .day, value: days, to: base)
        return .handled
    }

    private func stepTime(_ key: KeyEquivalent) -> KeyPress.Result {
        if key == .delete { edit.hasTime = false; return .handled }
        guard edit.hasTime else { edit.hasTime = true; return .handled }
        let minutes = key.step(small: 15, large: 60)
        edit.time = calendar.date(byAdding: .minute, value: minutes, to: edit.time) ?? edit.time
        return .handled
    }

    // MARK: Values

    private var listOptions: [(String?, String)] {
        [(nil, L10n.tr("quickaddeditorview.default", "Default"))] + lists.map { (Optional($0.id), $0.title) }
    }

    private var listTitle: String {
        lists.first { $0.id == edit.listID }?.title ?? L10n.tr("quickaddeditorview.default", "Default")
    }

    private var listColor: Color {
        lists.first { $0.id == edit.listID }?.color ?? theme.secondaryText
    }

    private func label(for field: QuickAddField) -> String {
        switch field {
        case .title: return L10n.tr("quickaddeditorview.title", "Title")
        case .list: return L10n.tr("quickaddeditorview.list", "List")
        case .date: return L10n.tr("quickaddeditorview.date", "Date")
        case .time: return L10n.tr("quickaddeditorview.time", "Time")
        case .priority: return L10n.tr("quickaddeditorview.priority", "Priority")
        case .recurrence: return L10n.tr("quickaddeditorview.repeat", "Repeat")
        case .repeatEnd: return RepeatEndPopover.title
        // The event form's fields; the task form never shows them.
        case .calendar, .endDate, .endTime, .location, .alert: return ""
        }
    }
}

/// Quick Add's grid geometry — one place, no per-row padding.
package enum QuickAddGrid {
    package static let labelWidth: CGFloat = 76
    package static let controlHeight: CGFloat = 24
    package static let rowSpacing: CGFloat = 6
    package static let headerGap: CGFloat = 10
    package static let menuControlWidth: CGFloat = 132
    package static let shortControlWidth: CGFloat = 100
    /// A time beside its date: narrower, and the same for start and end.
    package static let timeControlWidth: CGFloat = 64
}

/// The shared control surface: compact, graphite, a hairline edge; a
/// little stronger on hover; a restrained accent ring when focused. Never a
/// full-row highlight, never a blue fill.
package struct QuickAddControl: View {
    @Environment(\.themePalette) private var theme

    package let text: String
    package let isPlaceholder: Bool
    package let hasMenu: Bool
    package let isFocused: Bool
    package let minWidth: CGFloat
    @State private var isHovering = false

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        HStack(spacing: 6) {
            Text(text)
                .foregroundStyle(isPlaceholder ? theme.editor.placeholderText : theme.editor.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            if hasMenu {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.editor.labelText)
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: minWidth, alignment: .leading)
        .frame(height: QuickAddGrid.controlHeight - 2)
        .fixedSize(horizontal: true, vertical: false)
        .themedSurface(.control, fill: isFocused ? theme.editor.fieldFocusedFill : isHovering ? theme.editor.fieldHoverFill : theme.editor.fieldFill, in: shape)
        .overlay(shape.strokeBorder(theme.editor.fieldKeyline, lineWidth: 1))
        .overlay {
            if isFocused { shape.strokeBorder(theme.editor.focusRing, lineWidth: 1.5).padding(-1.5) }
        }
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isFocused)
    }
}

/// A choice list in a popover: ↑ / ↓ move, Return or Space choose, a click
/// chooses; Esc (the app's) closes it. It takes keyboard focus as it opens.
package struct QuickAddChoiceList<Value: Hashable>: View {
    @Environment(\.themePalette) private var theme

    package let options: [(Value, String)]
    package let selection: Value
    package let choose: (Value) -> Void

    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    package var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(options.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(options[index].0 == selection ? 1 : 0)
                    Text(options[index].1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .frame(minWidth: 150, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(index == highlighted ? theme.editor.selectionFill : Color.clear)
                )
                .foregroundStyle(index == highlighted ? theme.onAccentText : theme.primaryText)
                .contentShape(Rectangle())
                .onHover { if $0 { highlighted = index } }
                .onTapGesture { choose(options[index].0) }
            }
        }
        .padding(5)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            highlighted = options.firstIndex { $0.0 == selection } ?? 0
            isFocused = true
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            highlighted = press.key == .upArrow ? max(highlighted - 1, 0) : min(highlighted + 1, options.count - 1)
            return .handled
        }
        .onKeyPress(keys: [.return, .space]) { _ in
            choose(options[highlighted].0)
            return .handled
        }
    }
}
