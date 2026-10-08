import AppKit
import SwiftUI

/// The selector shared by Calendars and Reminder Lists, in the footer
/// selectors' grammar (`SelectorPopoverParts`): a passive title, sources
/// grouped by account (and an optional Smart group), then the commands —
/// Show All and the contextual Manage…. It stays open while toggling.
///
/// Mouse: click toggles, ⌥-click shows only that row.
/// Keyboard: ↑ ↓ move through rows and commands, Space or Return toggles
/// (or runs a command), ⌥Space solos, ⌘A shows all, Esc closes.
package struct SourceSelectionPopover: View {
    @Environment(\.themePalette) private var theme

    package let title: String
    package let groups: [SelectionGroup]
    package let emptyMessage: String
    /// "Show All Calendars", "Show All Lists".
    package let showAllTitle: String
    package let manageTitle: String
    package let canShowAll: Bool
    package let onToggle: (String) -> Void
    /// nil where solo doesn't apply (Smart sections).
    package let onSolo: (String) -> Void
    package let onShowAll: () -> Void
    package let onManage: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var focusedID: String?
    @FocusState private var isFocused: Bool

    private static let showAllID = "§command.showAll"
    private static let manageID = "§command.manage"

    private var allItems: [SelectionItem] { groups.flatMap(\.items) }

    /// Keyboard stops, top to bottom: the rows, then the commands that can act.
    private var stops: [String] {
        allItems.map(\.id) + (canShowAll ? [Self.showAllID] : []) + [Self.manageID]
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SelectorPopoverHeader(title: title)
            if allItems.isEmpty {
                SelectorPopoverEmptyText(text: emptyMessage)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                                .padding(.horizontal, SelectorPopoverMetrics.rowPaddingH)
                                .padding(.bottom, 2)
                            ForEach(group.items) { row($0) }
                        }
                    }
                }
            }
            SelectorPopoverSeparator()
            VStack(alignment: .leading, spacing: 1) {
                command(Self.showAllID, symbol: nil, title: showAllTitle, isEnabled: canShowAll, action: onShowAll)
                command(Self.manageID, symbol: "gearshape", title: manageTitle) {
                    dismiss()
                    onManage()
                }
            }
        }
        .padding(SelectorPopoverMetrics.padding)
        .frame(width: SelectorPopoverMetrics.width, alignment: .leading)
        .selectorPopoverSurface(theme)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(.downArrow) { moveFocus(1); return .handled }
        .onKeyPress(.upArrow) { moveFocus(-1); return .handled }
        .onKeyPress(.space, phases: .down) { press in activate(solo: press.modifiers.contains(.option)) }
        .onKeyPress(.return, phases: .down) { press in activate(solo: press.modifiers.contains(.option)) }
        .onKeyPress("a", phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            onShowAll()
            return .handled
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func command(_ id: String, symbol: String?, title: String, isEnabled: Bool = true,
                         action: @escaping () -> Void) -> some View {
        SelectorCommandRow(symbol: symbol, title: title, isEnabled: isEnabled, isFocused: focusedID == id) {
            focusedID = id
            action()
        }
        .onHover { if $0, isEnabled { focusedID = id } }
    }

    private func row(_ item: SelectionItem) -> some View {
        SelectionRow(item: item, isFocused: focusedID == item.id) {
            focusedID = item.id
            // Option at click time turns a toggle into "only this one".
            if NSEvent.modifierFlags.contains(.option) { onSolo(item.id) } else { onToggle(item.id) }
        }
        .onHover { if $0 { focusedID = item.id } }
    }

    private func activate(solo: Bool) -> KeyPress.Result {
        switch focusedID {
        case nil:
            break
        case Self.showAllID?:
            if canShowAll { onShowAll() }
        case Self.manageID?:
            dismiss()
            onManage()
        case let id?:
            if solo { onSolo(id) } else { onToggle(id) }
        }
        return .handled
    }

    private func moveFocus(_ delta: Int) {
        let ids = stops
        guard !ids.isEmpty else { return }
        let index = focusedID.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        focusedID = ids[min(max(index + delta, 0), ids.count - 1)]
    }

    package init(
        title: String,
        groups: [SelectionGroup],
        emptyMessage: String,
        showAllTitle: String,
        manageTitle: String,
        canShowAll: Bool,
        onToggle: @escaping (String) -> Void,
        onSolo: @escaping (String) -> Void,
        onShowAll: @escaping () -> Void,
        onManage: @escaping () -> Void
    ) {
        self.title = title
        self.groups = groups
        self.emptyMessage = emptyMessage
        self.showAllTitle = showAllTitle
        self.manageTitle = manageTitle
        self.canShowAll = canShowAll
        self.onToggle = onToggle
        self.onSolo = onSolo
        self.onShowAll = onShowAll
        self.onManage = onManage
    }
}

/// One row: a single leading indicator (never a second checkmark) + title.
private struct SelectionRow: View {
    @Environment(\.themePalette) private var theme

    let item: SelectionItem
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        let style = SelectorRowStyle(theme: theme, isHighlighted: isFocused)
        Button(action: action) {
            HStack(spacing: SelectorPopoverMetrics.iconToText) {
                SelectionIndicatorView(indicator: item.indicator, isSelected: item.isSelected)
                Text(verbatim: item.title)
                    .font(DetailMetrics.font)
                    .foregroundStyle(item.isSelected || isFocused ? style.primary : style.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SelectorPopoverMetrics.rowPaddingH)
            .frame(height: SelectorPopoverMetrics.rowHeight)
            // Hover and keyboard focus share one neutral fill; the source
            // color stays in the indicator alone.
            .background(SelectorRowBackground(isFocused: isFocused))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }
}

/// Selected: filled with the source color and a tiny check. Unselected: a
/// ring in the same color.
private struct SelectionIndicatorView: View {
    @Environment(\.themePalette) private var theme

    let indicator: SelectionIndicator
    let isSelected: Bool

    private var color: Color {
        switch indicator {
        case .color(let color): return color
        case .smart(.attention): return theme.tasks.attentionTint
        case .smart(.completed): return theme.secondaryText
        }
    }

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(color)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(theme.onAccentText)
            } else {
                Circle().strokeBorder(color.opacity(0.85), lineWidth: 1.5)
            }
        }
        .frame(width: 13, height: 13)
    }
}
