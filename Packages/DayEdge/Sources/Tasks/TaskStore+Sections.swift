import AppKit
import Observation
import SwiftUI
import Domain
import UI

extension TaskStore {
    // MARK: - Sections and navigation

    /// The landmarks the navigator, ← / → and the scrollspy work over.
    package func navigableSections(query: String = "") -> [TaskSection] {
        sections(query: query).filter(\.isNavigable)
    }

    /// The active section, falling back to the first landmark.
    package func currentSectionID(query: String = "") -> String? {
        let ids = navigableSections(query: query).map(\.id)
        if let activeSectionID, ids.contains(activeSectionID) { return activeSectionID }
        return ids.first
    }

    /// Scrolls the section to the top and makes it current — chip click,
    /// header click. Task selection is left alone.
    package func jump(to sectionID: String) {
        activeSectionID = sectionID
        jumpRequest = JumpRequest(sectionID: sectionID)
    }

    /// ← / →: jump to the neighbouring landmark and select its first task.
    package func moveSection(_ delta: Int, query: String) {
        let all = navigableSections(query: query)
        guard !all.isEmpty else { return }
        let ids = all.map(\.id)
        let current = currentSectionID(query: query).flatMap { ids.firstIndex(of: $0) } ?? 0
        let target = min(max(current + delta, 0), ids.count - 1)
        jump(to: ids[target])
        selectedTaskID = all[target].tasks.first?.id
    }

    /// Scrollspy update from manual scrolling; never moves the view.
    package func setActiveSectionFromScroll(_ id: String?) {
        guard let id, id != activeSectionID else { return }
        activeSectionID = id
    }

    // MARK: - Sorting

    /// Re-sorts list sections. Selection and the active section stay put;
    /// the selected row is revealed at its new position.
    package func setSort(_ mode: TaskSortMode, direction: TaskSortDirection? = nil) {
        let newDirection = direction ?? sortDirection
        guard mode != sortMode || newDirection != sortDirection else { return }
        sortMode = mode
        sortDirection = newDirection
        defaults.set(mode.rawValue, forKey: Self.sortModeKey)
        defaults.set(newDirection.rawValue, forKey: Self.sortDirectionKey)
        if let selectedTaskID, sections(query: "").contains(where: { $0.tasks.contains { $0.id == selectedTaskID } }) {
            scrollRequest = ScrollRequest(taskID: selectedTaskID)
        }
    }

    package var sortAccessibilityValue: String {
        sortMode.hasDirection ? "\(sortMode.title), \(sortMode.directionTitle(sortDirection))" : sortMode.title
    }

    package func toggleExpanded(_ sectionID: String) {
        if expandedSectionIDs.contains(sectionID) { expandedSectionIDs.remove(sectionID) } else { expandedSectionIDs.insert(sectionID) }
        dropSelectionIfHidden()
    }

    /// A selection folded away with its rows would be invisible.
    func dropSelectionIfHidden() {
        guard let selectedTaskID else { return }
        if !sections(query: "").contains(where: { $0.tasks.contains { $0.id == selectedTaskID } }) {
            self.selectedTaskID = nil
        }
    }

    // MARK: - Sections

    package func sections(query: String) -> [TaskSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = now()
        let key = CacheKey(
            revision: revision, expanded: expandedSectionIDs, query: trimmed,
            completedExpanded: completedExpanded, completedLimit: completedLimit,
            sortMode: sortMode, sortDirection: sortDirection,
            hidden: listVisibility.hiddenIDs, excluded: listVisibility.excludedIDs, lingering: lingeringIDs,
            minute: Int(current.timeIntervalSince1970 / 60)
        )
        if let cache, cache.key == key { return cache.sections }

        // A hidden or excluded list leaves the document entirely.
        let shownTasks = tasks.filter { listVisibility.isVisible($0.listID) }
        let shownLists = lists.filter { listVisibility.isVisible($0.id) }

        let computed: [TaskSection]
        if trimmed.isEmpty {
            computed = TaskBuckets.sections(
                tasks: shownTasks, lists: shownLists, now: current, calendar: calendar,
                options: TaskBucketOptions(
                    expandedSectionIDs: expandedSectionIDs, completedExpanded: completedExpanded,
                    showsAttention: isSmartVisible(.attention), showsCompleted: isSmartVisible(.completed),
                    completedLimit: completedLimit,
                    sortMode: sortMode, sortDirection: sortDirection
                ),
                lingeringIDs: lingeringIDs,
                placementOverrides: placementSnapshots
            )
        } else {
            computed = TaskBuckets.searchResults(tasks: shownTasks, query: trimmed, now: current, calendar: calendar)
        }
        cache = (key, computed)
        return computed
    }

    /// The line under "Tasks".
    package func headerSubtitle(query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let count = sections(query: trimmed).first?.totalCount ?? 0
            return L10n.tr("tasks.search.results", "\(count) results")
        }
        let attention = sections(query: "").first { $0.kind == .needsAttention }?.totalCount ?? 0
        guard attention > 0 else { return nil }
        return L10n.tr("tasks.attention.count", "\(attention) need attention")
    }

    package func list(for task: TaskItem) -> CalendarSource? { lists.first { $0.id == task.listID } }

    package func dueText(for task: TaskItem, format: TimeFormat) -> TaskDueText? {
        TaskBuckets.dueText(for: task, now: now(), calendar: calendar, format: format)
    }
}
