import AppKit
import Observation
import SwiftUI
import Domain
import UI

extension TaskStore {
    // MARK: - Visibility (footer selector)

    package func isSmartVisible(_ section: TaskSmartSection) -> Bool {
        !listVisibility.hiddenIDs.contains(section.visibilityID)
    }

    /// Groups for the selector: lists by account, then the Smart group.
    package var selectorGroups: [SelectionGroup] {
        SelectionGroups.bySource(listVisibility.availableItems, kind: .reminderList) { [listVisibility] in
            listVisibility.isVisible($0)
        } + [SelectionGroups.smart { [self] in isSmartVisible($0) }]
    }

    package func toggleVisibility(_ id: String) { listVisibility.toggle(id) }

    /// ⌥-click: show only this list. Smart sections are left as they are.
    package func solo(_ id: String) {
        guard !TaskSmartSection.allCases.contains(where: { $0.visibilityID == id }) else { return }
        listVisibility.solo(id, among: listVisibility.availableItems.map(\.id))
    }

    package func toggleCompletedExpanded() {
        completedExpanded.toggle()
        // Folding back up forgets how far it was paged.
        if !completedExpanded {
            completedLimit = TaskBucketOptions.completedBatch
            dropSelectionIfHidden()
        }
    }

    /// Reveals the next batch of completed tasks.
    package func showMoreCompleted() { completedLimit += TaskBucketOptions.completedBatch }

    package func completionText(for task: TaskItem) -> String? {
        TaskBuckets.completionText(for: task, now: now(), calendar: calendar)
    }
}
