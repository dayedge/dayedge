import SwiftUI
import Domain
import UI

/// The rail's sort control, styled as a toolbar option rather than another
/// section chip: borderless at rest ("⇅ Priority ⌄"), a soft rounded fill on
/// hover, and a slightly stronger one while the menu is open. Always shows
/// the current mode; never colored.
package struct TaskSortButton: View {
    @Environment(\.themePalette) private var theme

    package let store: TaskStore

    @State private var isHovering = false

    private var isOpen: Bool { store.isSortMenuPresented }

    private var fill: Color {
        if isOpen { return theme.secondaryControl.pressed }
        return isHovering ? theme.secondaryControl.hover : .clear
    }

    package var body: some View {
        @Bindable var store = store
        Button { store.isSortMenuPresented.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.secondaryText.opacity(isOpen || isHovering ? 1 : 0.8))
                Text(store.sortMode.shortTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText.opacity(isOpen || isHovering ? 0.9 : 0.7))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.content.detailMetadata)
            }
            .padding(.horizontal, 7)
            // A modest floor keeps the width from jittering between
            // "Smart" and "Title".
            .frame(minWidth: 70, minHeight: 24)
            .themedSurface(.floatingControl, fill: fill,
                             in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .hoverTooltip(L10n.tr("tasksortmenuview.sort.tasks", "Sort tasks"),
                      shortcut: KeyboardShortcutSettings.shared.shortcut(for: .action(.openSortMenu))?.displayLabel, edge: .bottom)
        .popover(isPresented: $store.isSortMenuPresented, arrowEdge: .bottom) {
            TaskSortMenuView(store: store)
        }
        .accessibilityLabel(L10n.tr("tasksortmenuview.sort.tasks", "Sort tasks"))
        .accessibilityValue(store.sortAccessibilityValue)
        .accessibilityAddTraits(.isButton)
    }
}

/// A flat, keyboard-driven menu: ↑ / ↓ move, Return applies, Esc closes.
/// Direction rows use plain language ("Soonest First") and are hidden for
/// Smart, which defines its own order. Drawn like the footer selectors and
/// the property editors (`SelectorPopoverParts`): passive title, menu rows
/// with the accent highlight, the system popover material.
package struct TaskSortMenuView: View {
    @Environment(\.themePalette) private var theme

    package let store: TaskStore

    private enum Item: Hashable {
        case mode(TaskSortMode)
        case direction(TaskSortDirection)
    }

    @State private var highlighted: Item?
    @FocusState private var isFocused: Bool

    private var items: [Item] {
        store.availableSortModes.map(Item.mode)
            + (store.sortMode.hasDirection ? TaskSortDirection.allCases.map(Item.direction) : [])
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            SelectorPopoverHeader(title: L10n.tr("tasksortmenuview.sort.tasks.80abde", "Sort Tasks"))

            ForEach(store.availableSortModes) { mode in
                row(.mode(mode), title: mode.title, isOn: store.sortMode == mode)
            }

            if store.sortMode.hasDirection {
                SelectorPopoverSeparator()
                ForEach(TaskSortDirection.allCases, id: \.self) { direction in
                    row(.direction(direction), title: store.sortMode.directionTitle(direction),
                        isOn: store.sortDirection == direction)
                }
            }
        }
        .padding(SelectorPopoverMetrics.padding)
        .frame(minWidth: 190, alignment: .leading)
        .selectorPopoverSurface(theme)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
            highlighted = .mode(store.sortMode)
        }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) {
            if let highlighted { apply(highlighted) }
            return .handled
        }
    }

    private func row(_ item: Item, title: String, isOn: Bool) -> some View {
        let style = SelectorRowStyle(theme: theme, isHighlighted: highlighted == item)
        return Button { apply(item) } label: {
            HStack(spacing: SelectorPopoverMetrics.iconToText) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.primary)
                    .frame(width: SelectorPopoverMetrics.iconColumn)
                    .opacity(isOn ? 1 : 0)
                Text(title)
                    .font(DetailMetrics.font)
                    .foregroundStyle(style.primary)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, SelectorPopoverMetrics.rowPaddingH)
            .frame(height: SelectorPopoverMetrics.rowHeight)
            .background(SelectorRowBackground(isFocused: highlighted == item))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = item } }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func move(_ delta: Int) {
        let all = items
        guard !all.isEmpty else { return }
        let index = highlighted.flatMap { all.firstIndex(of: $0) } ?? -1
        highlighted = all[min(max(index + delta, 0), all.count - 1)]
    }

    /// Picking a mode or a direction applies it and closes, like a menu.
    private func apply(_ item: Item) {
        switch item {
        case .mode(let mode): store.setSort(mode)
        case .direction(let direction): store.setSort(store.sortMode, direction: direction)
        }
        store.isSortMenuPresented = false
    }
}
