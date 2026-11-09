import SwiftUI
import Domain
import UI

/// The Command Window's Tasks header: the title and counts, the sort
/// control beside them — the lists are in the sidebar.
package struct TasksTitleHeader: View {
    package let store: TaskStore
    package let query: String

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    package var body: some View {
        LargeTitleHeader {
            // The filter picked in the sidebar names the document.
            Text(store.filter == .all || isSearching ? L10n.tr("tasksview.tasks", "Tasks") : store.filter.title)
        } subtitle: {
            if let subtitle = store.headerSubtitle(query: query) {
                PeriodHeaderSubtitle(text: subtitle)
            }
        } trailing: {
            TaskSortButton(store: store)
        }
    }

    package init(store: TaskStore, query: String) {
        self.store = store
        self.query = query
    }
}
