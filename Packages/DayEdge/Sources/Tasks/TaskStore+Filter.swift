import Foundation
import Domain
import UI

extension TaskStore {
    // MARK: - Filter

    /// A hidden or excluded list leaves Tasks entirely.
    var shownTasks: [TaskItem] { tasks.filter { listVisibility.isVisible($0.listID) } }
    package var shownLists: [CalendarSource] { lists.filter { listVisibility.isVisible($0.id) } }

    /// The Overview rows and keys on offer (Needs Attention only while
    /// its section is on).
    package var smartViews: [TaskSmartView] {
        TaskSmartView.allCases.filter { $0 != .attention || isSmartVisible(.attention) }
    }

    /// Shows a filter from the top; selection goes if its task isn't there.
    package func select(_ filter: TaskFilter) {
        self.filter = filter
        activeSectionID = nil
        jumpRequest = sections(query: "").first.map { JumpRequest(sectionID: $0.id) }
        dropSelectionIfHidden()
    }

    /// Jumps to a section (`TaskSection.Kind.id`); All Tasks first when
    /// the filter leaves it out.
    package func show(section id: String) {
        if !sections(query: "").contains(where: { $0.id == id }) { filter = .all }
        jump(to: id)
    }

    /// Every filter's count at once — the sidebar's and the menu's.
    package var filterCounts: [TaskFilter: Int] {
        let current = now()
        let key = cacheKey(query: "", at: current)
        if let hit = countsCache, hit.key == key { return hit.counts }
        let counts = TaskFilter.counts(tasks: shownTasks, now: current, calendar: calendar)
        countsCache = (key, counts)
        return counts
    }
}
