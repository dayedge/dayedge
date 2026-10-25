import SwiftUI
import Domain
import UI

/// What the task and event forms share: the control family, choice controls, Repeat and End Repeat, with the focus and
/// the open editor they move between. Each control takes its own rules where it is placed: how the arrow keys step it
/// while closed, and what opening it does first.
struct QuickAddForm {
    let focus: FocusState<QuickAddField?>.Binding
    let openEditor: Binding<QuickAddField?>
    let repeating: Binding<RepeatEdit>
    let calendar: Calendar
    let dateFormatter: DatePresentationFormatter
    /// Each field's spoken name.
    let name: (QuickAddField) -> String

    /// A day as both forms show one: compact, in the user's locale.
    func format(_ day: Date) -> String { dateFormatter.format(day, .short, year: .always) }

    /// One control family: the value on a compact graphite surface (with a chevron for choices), a restrained focus
    /// ring, and a popover editor opened by Space, Return or a click. `step` takes ←, →, ↑, ↓ and Delete while it is
    /// closed; `prepare` runs as it opens (Time on an all-day event makes it timed).
    func control<Editor: View>(_ field: QuickAddField, value: String?, placeholder: String, hasMenu: Bool = false,
                               minWidth: CGFloat, step: ((KeyEquivalent) -> KeyPress.Result)? = nil,
                               prepare: @escaping () -> Void = {}, @ViewBuilder editor: @escaping () -> Editor) -> some View {
        let open = {
            focus.wrappedValue = field
            prepare()
            openEditor.wrappedValue = field
        }
        return QuickAddControl(
            text: value ?? placeholder,
            isPlaceholder: value == nil,
            hasMenu: hasMenu,
            isFocused: focus.wrappedValue == field,
            minWidth: minWidth
        )
        .quickAddControl(field, focus: focus, open: open)
        .onKeyPress(keys: step == nil ? [] : [.leftArrow, .rightArrow, .upArrow, .downArrow, .delete]) { press in
            step?(press.key) ?? .ignored
        }
        .popover(isPresented: Binding(get: { openEditor.wrappedValue == field },
                                      set: { if !$0, openEditor.wrappedValue == field { openEditor.wrappedValue = nil } }),
                 arrowEdge: .bottom) {
            editor()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name(field))
        .accessibilityValue(value ?? placeholder)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }

    /// A popup-style control whose editor is a keyboard-navigable choice list; ← / → choose the next one closed.
    func choice<Value: Hashable>(_ field: QuickAddField, value: String, options: [(Value, String)],
                                 selection: Value, choose: @escaping (Value) -> Void) -> some View {
        control(field, value: value, placeholder: "", hasMenu: true, minWidth: QuickAddGrid.menuControlWidth) {
            QuickAddChoiceList(options: options, selection: selection) { value in
                choose(value)
                close()
            }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard let index = options.firstIndex(where: { $0.0 == selection }) else { return .ignored }
            let step = press.key == .rightArrow ? 1 : -1
            choose(options[(index + step + options.count) % options.count].0)
            return .handled
        }
    }

    /// Repeat, with the parsed rule the menu can't express while it is selected.
    var repeatChoice: some View {
        let edit = repeating.wrappedValue
        return choice(.recurrence, value: edit.recurrence.title, options: edit.options.map { ($0, $0.title) },
                      selection: edit.recurrence) { repeating.wrappedValue.recurrence = $0 }
    }

    /// End Repeat's row, while it repeats: opened from Never it starts at the suggested end, and its keys step the last
    /// day (`RepeatEdit.handle`).
    @ViewBuilder func repeatEndRow(firstDay: Date) -> some View {
        if repeating.wrappedValue.isRepeating {
            QuickAddRow(RepeatEndPopover.title) {
                control(.repeatEnd, value: repeating.wrappedValue.lastDay.map(format), placeholder: RepeatEndPopover.never,
                        minWidth: QuickAddGrid.shortControlWidth,
                        step: { repeating.wrappedValue.handle($0, firstDay: firstDay, calendar: calendar) },
                        prepare: { repeating.wrappedValue.startEnd(firstDay: firstDay, calendar: calendar) },
                        editor: { RepeatEndPopover(lastDay: repeating.lastDay, firstDay: firstDay, calendar: calendar, close: close) })
            }
        }
    }

    func close() { openEditor.wrappedValue = nil }
}

/// A label, then its controls side by side (an event's Starts and Ends hold a date and a time), on Quick Add's grid.
/// The form indents the rows together, so labels line up with the header's title.
struct QuickAddRow<Controls: View>: View {
    @Environment(\.themePalette) private var theme

    private let label: String
    private let controls: Controls

    init(_ label: String, @ViewBuilder controls: () -> Controls) {
        self.label = label
        self.controls = controls()
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .foregroundStyle(theme.editor.labelText)
                .frame(width: QuickAddGrid.labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: QuickAddGrid.rowSpacing) { controls }
            Spacer(minLength: 0)
        }
        .frame(height: QuickAddGrid.controlHeight)
    }
}
