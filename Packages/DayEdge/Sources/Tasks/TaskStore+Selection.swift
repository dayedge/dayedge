import AppKit
import Observation
import SwiftUI
import Domain
import UI

extension TaskStore {
    // MARK: - Arrival

    package func markArrival(_ id: String) {
        arrivingTaskID = id
        arrivalTask?.cancel()
        arrivalTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.arrivingTaskID = nil
        }
    }

    // MARK: - Revealing one task ("Show in Tasks")

    /// Brings `id` into view in the Tasks document: where Tasks keeps it
    /// (Needs attention, its list, or Completed), made visible, expanded as
    /// far as needed, selected, and scrolled to — so ↑ / ↓, Return, Space
    /// and ← / → carry on from it. False when Tasks doesn't hold that task
    /// (nothing is faked).
    @discardableResult
    package func reveal(_ id: String) -> Bool {
        guard let task = tasks.first(where: { $0.id == id }) else { return false }
        // A list hidden by the footer filter is shown again; one excluded in
        // Settings has no tasks loaded at all, so it never gets here.
        if listVisibility.hiddenIDs.contains(task.listID) { listVisibility.toggle(task.listID) }
        if task.isCompleted, !isSmartVisible(.completed) { listVisibility.toggle(TaskSmartSection.completed.visibilityID) }
        setPresented(nil)

        guard let sectionID = sectionID(containing: id) else { return false }
        if sectionID == "completed" {
            if !completedExpanded { toggleCompletedExpanded() }
            // Completed pages in batches: grow until the task is shown.
            while !isShown(id), completedLimit < tasks.count { completedLimit += TaskBucketOptions.completedBatch }
        } else if !isShown(id) {
            expandedSectionIDs.insert(sectionID)
        }
        selectedTaskID = id
        activeSectionID = sectionID
        scrollRequest = ScrollRequest(taskID: id)
        return true
    }

    private func isShown(_ id: String) -> Bool {
        sections(query: "").contains { $0.tasks.contains { $0.id == id } }
    }

    /// The section that holds `id` once everything is expanded.
    func sectionID(containing id: String) -> String? {
        let shownTasks = tasks.filter { listVisibility.isVisible($0.listID) }
        let shownLists = lists.filter { listVisibility.isVisible($0.id) }
        let everything = TaskBuckets.sections(
            tasks: shownTasks, lists: shownLists, now: now(), calendar: calendar,
            options: TaskBucketOptions(
                expandedSectionIDs: Set(["attention"] + shownLists.map { "list-\($0.id)" }),
                completedExpanded: true,
                showsAttention: isSmartVisible(.attention), showsCompleted: isSmartVisible(.completed),
                completedLimit: .max, sortMode: sortMode, sortDirection: sortDirection
            ),
            lingeringIDs: lingeringIDs, placementOverrides: placementSnapshots
        )
        return everything.first { $0.tasks.contains { $0.id == id } }?.id
    }

    // MARK: - Selection and details

    package func select(_ id: String?) { selectedTaskID = id }

    package func moveSelection(_ direction: VerticalNavigationDirection, query: String) {
        let ids = sections(query: query).flatMap { $0.tasks.map(\.id) }
        guard !ids.isEmpty else { return }
        let next: String
        if let current = selectedTaskID, let index = ids.firstIndex(of: current) {
            let target = direction == .up ? max(index - 1, 0) : min(index + 1, ids.count - 1)
            next = ids[target]
        } else {
            next = ids[0]
        }
        selectedTaskID = next
        scrollRequest = ScrollRequest(taskID: next)
        // Moving through tasks carries the "you are here" marker along.
        if let section = sections(query: query).first(where: { $0.tasks.contains { $0.id == next } }), section.isNavigable {
            activeSectionID = section.id
        }
    }

    package func toggleDetail(for id: String) {
        setPresented(presentedDetailID == id ? nil : id)
    }

    package func setDetailPresented(_ presented: Bool, for id: String) {
        if presented { setPresented(id) } else if presentedDetailID == id { setPresented(nil) }
    }

    /// Opening snapshots the task for placement; closing lets it settle
    /// into wherever its edits put it.
    func setPresented(_ id: String?) {
        guard id != presentedDetailID else { return }
        let hadSnapshot = !placementSnapshots.isEmpty
        placementSnapshots = [:]
        presentedDetailID = id
        if let id, let task = tasks.first(where: { $0.id == id }) { placementSnapshots[id] = task }
        if hadSnapshot || !placementSnapshots.isEmpty {
            withAnimation(.smooth(duration: 0.3)) { presentationRevision += 1 }
        }
    }

    /// Return: the selected task's details — or, with nothing selected
    /// while Completed is the current section, fold/unfold Completed.
    package func toggleDetailForSelection() {
        if let selectedTaskID {
            toggleDetail(for: selectedTaskID)
        } else if currentSectionID() == "completed" {
            toggleCompletedExpanded()
        }
    }

    /// Returns true when a popover was open and is now closed.
    @discardableResult
    package func dismissDetail() -> Bool {
        guard presentedDetailID != nil else { return false }
        setPresented(nil)
        return true
    }
}
