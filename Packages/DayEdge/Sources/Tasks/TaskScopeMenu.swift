import SwiftUI
import Domain
import UI

/// The popover's filter beside the Tasks title: Today, Next 7 Days, All
/// Tasks. A native menu — it shows their ⌥⌘ keys itself and owns the
/// keyboard while open. The chips below are the filtered list's sections.
package struct TaskScopeMenu: View {
    package let store: TaskStore

    @State private var isHovering = false

    package var body: some View {
        let counts = store.filterCounts
        Menu {
            ForEach(TaskFilter.allCases, id: \.self) { filter in
                Toggle(isOn: Binding(get: { filter == store.filter }, set: { _ in store.select(filter) })) {
                    Text(verbatim: filter.title)
                }
                .badge(counts[filter] ?? 0)
                .keyboardShortcut(KeyboardShortcutSettings.shared.shortcut(for: .taskView(filter.smartView))?.swiftUIShortcut)
            }
        } label: {
            TaskRailButtonLabel(symbol: nil, title: store.filter.title, isOpen: false, isHovering: isHovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .accessibilityLabel(L10n.tr("taskscopemenu.label", "Tasks view"))
        .accessibilityValue(store.filter.title)
    }

    package init(store: TaskStore) {
        self.store = store
    }
}
