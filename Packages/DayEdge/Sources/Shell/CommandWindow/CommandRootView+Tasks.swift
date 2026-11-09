import SwiftUI
import Domain
import UI
import Tasks

extension CommandRootView {
    /// Tasks: its views (Overview, the lists, Completed) beside the task
    /// document — Day's geometry, the popover's document, rows, details
    /// and menus.
    var tasksWorkspace: some View {
        let store = models.taskStore
        let query = router.searchQuery
        return HStack(spacing: 0) {
            TaskSidebarView(store: store)
                .takesOfferedSize(width: AppTheme.CommandWindow.sidebarWidth)

            WorkspaceRule(.structural, axis: .vertical)

            TasksView(store: store, query: query,
                      isActive: isColumnShown(.tasks),
                      navigationRequest: verticalNavigationRequest) {
                TasksTitleHeader(store: store, query: query)
            }
            .takesOfferedSize()
        }
    }
}
