import SwiftUI
import Domain
import UI

/// The popover's Tasks header: the title and counts beside the view menu,
/// then the navigator chips beside the sort control (hidden while
/// searching).
package struct TasksNavigatorHeader: View {
    @Environment(\.themePalette) private var theme

    package let store: TaskStore
    package let query: String

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeTitleHeader {
                Text(L10n.tr("tasksview.tasks", "Tasks"))
            } subtitle: {
                if let subtitle = store.headerSubtitle(query: query) {
                    PeriodHeaderSubtitle(text: subtitle)
                }
            } trailing: {
                // Search spans every list, whatever the view.
                if !isSearching { TaskScopeMenu(store: store) }
            }

            if !isSearching {
                let items = TaskNavigatorItem.items(from: store.sections(query: ""))
                if !items.isEmpty {
                    // Location (scrolling chips) and arrangement (a fixed
                    // sort control) stay separate: the button never
                    // scrolls away with the chips.
                    HStack(spacing: 0) {
                        TaskNavigatorView(
                            items: items,
                            activeID: store.currentSectionID(query: query),
                            trailingInset: 12,
                            onSelect: { store.jump(to: $0) }
                        )
                        Rectangle()
                            .fill(theme.secondaryControl.divider)
                            .frame(width: 1, height: 16)
                        TaskSortButton(store: store)
                            .padding(.leading, 10)
                            .padding(.trailing, AppTheme.horizontalPadding - 4)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    package init(store: TaskStore, query: String) {
        self.store = store
        self.query = query
    }
}
