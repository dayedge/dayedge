import SwiftUI
import Domain

/// One row of a `ChoiceListEditor`.
package struct ChoiceItem: Identifiable, Equatable {
    package enum Kind: Equatable {
        /// A value: choosing it applies it.
        case choice
        /// Opens a page in the same editor ("Custom…", "At a Specific Time…").
        case more
        case separator
    }

    package let id: String
    package var title: String = ""
    package var isChecked = false
    package var kind: Kind = .choice

    package static func separator(_ id: String) -> ChoiceItem { ChoiceItem(id: id, kind: .separator) }
}

/// The selection-menu grammar inside a property editor — used where a
/// choice can morph into a page of its own (Repeat → Custom…, Alert → At
/// a Specific Time…) and where the card's keyboard must be able to open it
/// (a native menu can't be opened from code). Looks like a menu: checkmark
/// column, highlighted row, separators. ↑ / ↓ move, ↩ chooses, Esc closes
/// (the popover's own). Keys stay here: the editor is its own popover.
package struct ChoiceListEditor: View {
    @Environment(\.themePalette) private var theme

    package let items: [ChoiceItem]
    package let onChoose: (ChoiceItem) -> Void

    @State private var highlighted: String?
    @FocusState private var isFocused: Bool

    private var selectable: [ChoiceItem] { items.filter { $0.kind != .separator } }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                if item.kind == .separator {
                    Divider()
                        .overlay(theme.chrome.divider)
                        .padding(.vertical, 4)
                } else {
                    row(item)
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            highlighted = (items.first { $0.isChecked } ?? selectable.first)?.id
            isFocused = true
        }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) {
            if let item = selectable.first(where: { $0.id == highlighted }) { onChoose(item) }
            return .handled
        }
    }

    private func row(_ item: ChoiceItem) -> some View {
        let isHighlighted = highlighted == item.id
        return HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .opacity(item.isChecked ? 1 : 0)
                .frame(width: 12)
            Text(verbatim: item.title)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(DetailMetrics.font)
        .foregroundStyle(isHighlighted ? theme.onAccentText : theme.primaryText)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHighlighted ? theme.nativeControlAccent : .clear)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { highlighted = item.id } }
        .onTapGesture { onChoose(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isChecked ? [.isButton, .isSelected] : .isButton)
    }

    private func move(_ step: Int) {
        guard !selectable.isEmpty else { return }
        let index = selectable.firstIndex { $0.id == highlighted } ?? (step > 0 ? -1 : selectable.count)
        highlighted = selectable[min(max(index + step, 0), selectable.count - 1)].id
    }
}

// MARK: - Repeat

/// Repeat, for events and tasks alike: Calendar's presets read from the
/// item's own date, then Custom… — which morphs this same editor into the
/// custom rule page (no second popover).
package struct RepeatEditor: View {
    /// The current rule; nil = never.
    package let current: TaskRecurrenceRule?
    package let anchor: Date
    /// The new rule (nil = never). Closes the editor.
    package let onChoose: (TaskRecurrenceRule?) -> Void

    private enum Page { case list, custom }

    @State private var page = Page.list
    @State private var draft: CustomRepeatDraft?

    private var calendar: Calendar { .autoupdatingCurrent }

    package var body: some View {
        switch page {
        case .list:
            PropertyEditor(width: .standard) {
                ChoiceListEditor(items: items) { item in
                    if item.id == "custom" {
                        draft = CustomRepeatDraft(rule: current, anchor: anchor, calendar: calendar)
                        page = .custom
                    } else if item.id == "current" {
                        onChoose(current) // already the rule
                    } else if let option = options.first(where: { $0.id == item.id }) {
                        onChoose(option.rule)
                    }
                }
            }
        case .custom:
            PropertyEditor(width: .wide, onCancel: { page = .list }, onDone: {
                if let draft { onChoose(draft.rule) }
            }, content: {
                if let binding = Binding($draft) { CustomRepeatForm(draft: binding) }
            })
        }
    }

    private var options: [RepeatOption] { RepeatPresets.options(anchor: anchor, calendar: calendar) }

    private var items: [ChoiceItem] {
        let matched = RepeatPresets.option(matching: current, in: options, anchor: anchor, calendar: calendar)
        var items = options.map { ChoiceItem(id: $0.id, title: $0.title, isChecked: $0.id == matched?.id) }
        items.insert(.separator("after-never"), at: 1)
        if matched == nil, let current {
            // A rule no preset expresses shows as itself, checked.
            items.append(.separator("before-current"))
            items.append(ChoiceItem(id: "current", title: current.summary, isChecked: true))
        }
        items.append(.separator("before-custom"))
        items.append(ChoiceItem(id: "custom", title: L10n.tr("choicelisteditor.custom", "Custom…"), kind: .more))
        return items
    }
}

/// Every [n] [unit] · on [weekdays] · Ends: Never / On date / After n.
private struct CustomRepeatForm: View {
    @Environment(\.themePalette) private var theme

    @Binding var draft: CustomRepeatDraft

    private static let units: [(TaskRecurrenceRule.Frequency, String)] = [
        (.daily, L10n.tr(
            "choicelisteditor.days", "Days"
        )), (.weekly, L10n.tr(
            "choicelisteditor.weeks", "Weeks"
        )), (.monthly, L10n.tr(
            "choicelisteditor.months", "Months"
        )), (.yearly, L10n.tr(
            "choicelisteditor.years", "Years"
        ))
    ]
    /// Monday first; `Calendar` weekday numbers.
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    private static let letters = [1: "S", 2: "M", 3: "T", 4: "W", 5: "T", 6: "F", 7: "S"]

    private enum EndKind: Hashable { case never, onDate, afterCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PropertyEditorField(label: "Repeat every") {
                HStack(spacing: 6) {
                    TextField("", value: $draft.interval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 40)
                    Picker("", selection: $draft.frequency) {
                        ForEach(Self.units, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if draft.frequency == .weekly {
                HStack(spacing: 4) {
                    ForEach(Self.weekdayOrder, id: \.self) { weekday in
                        let isOn = draft.weekdays.contains(weekday)
                        Button {
                            if isOn, draft.weekdays.count > 1 { draft.weekdays.remove(weekday) } else { draft.weekdays.insert(weekday) }
                        } label: {
                            Text(Self.letters[weekday] ?? "")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 22)
                                .foregroundStyle(isOn ? theme.onAccentText : theme.primaryText)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(isOn ? theme.nativeControlAccent : theme.detail.hoverFill)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(RepeatPresets.weekdayName(weekday, calendar: .autoupdatingCurrent))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("choicelisteditor.ends", "Ends")).foregroundStyle(theme.secondaryText)
                Picker("", selection: endKind) {
                    Text(L10n.tr("choicelisteditor.never", "Never")).tag(EndKind.never)
                    HStack {
                        Text(L10n.tr("choicelisteditor.on", "On"))
                        DatePicker("", selection: endDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .disabled(endKind.wrappedValue != .onDate)
                    }
                    .tag(EndKind.onDate)
                    HStack {
                        Text(L10n.tr("choicelisteditor.after", "After"))
                        TextField("", value: count, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 40)
                            .disabled(endKind.wrappedValue != .afterCount)
                        Text("times")
                    }
                    .tag(EndKind.afterCount)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
    }

    private var endKind: Binding<EndKind> {
        Binding {
            switch draft.ending {
            case .never: return .never
            case .onDate: return .onDate
            case .afterCount: return .afterCount
            }
        } set: { kind in
            switch kind {
            case .never: draft.ending = .never
            case .onDate: draft.ending = .onDate(Calendar.autoupdatingCurrent.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            case .afterCount: draft.ending = .afterCount(5)
            }
        }
    }

    private var endDate: Binding<Date> {
        Binding {
            if case .onDate(let date) = draft.ending { return date }
            return Calendar.autoupdatingCurrent.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        } set: { draft.ending = .onDate($0) }
    }

    private var count: Binding<Int> {
        Binding {
            if case .afterCount(let count) = draft.ending { return count }
            return 5
        } set: { draft.ending = .afterCount(max($0, 1)) }
    }
}

// MARK: - Alert

/// Alert, for events and tasks: presets in the item's own wording, then
/// "At a Specific Time…", which morphs this same editor into a date and
/// time page.
package struct AlertEditor: View {
    /// None, the presets (checked as they apply), with their ids.
    package let items: [ChoiceItem]
    /// Where the specific-time page starts.
    package let specificStart: Date
    package let onChoose: (ChoiceItem) -> Void
    package let onSpecific: (Date) -> Void

    @State private var isSpecific = false
    @State private var draft = Date()

    package var body: some View {
        if isSpecific {
            PropertyEditor(width: .fit, onCancel: { isSpecific = false }, onDone: { onSpecific(draft) }, content: {
                // The day on the calendar, the time as a plain field below
                // it (the graphical clock is too much for an alert).
                PropertyEditorCalendar(selection: $draft)
                PropertyEditorField(label: "Time") {
                    DatePicker(L10n.tr("choicelisteditor.time", "Time"), selection: $draft, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                }
            })
        } else {
            PropertyEditor(width: .standard) {
                ChoiceListEditor(items: items + [.separator("before-specific"),
                                                 ChoiceItem(id: "specific", title: L10n.tr("choicelisteditor.at.a.specific.time", "At a Specific Time…"), kind: .more)]) { item in
                    if item.id == "specific" {
                        draft = specificStart
                        isSpecific = true
                    } else {
                        onChoose(item)
                    }
                }
            }
        }
    }
}

// MARK: - Placement

extension View {
    /// Every property editor opens the same way: anchored to its row, on the
    /// leading side (away from the panel), flipped by the system at screen
    /// edges. One place to change it.
    package func propertyEditor<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        popover(isPresented: isPresented, arrowEdge: .leading, content: content)
    }
}
