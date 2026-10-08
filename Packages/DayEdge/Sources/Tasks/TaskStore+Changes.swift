import AppKit
import Observation
import SwiftUI
import Domain
import UI

extension TaskStore {
    // MARK: - Changes

    package func perform(_ action: TaskAction, on task: TaskItem) {
        switch action {
        case .complete, .uncomplete: toggleCompleted(task.id, closingDetail: presentedDetailID == task.id)
        default: actions.perform(action, on: task, now: now(), calendar: calendar) { [weak self] in self?.forget(task.id) }
        }
    }

    package func completeSelected() {
        guard let selectedTaskID else {
            if currentSectionID() == "completed" { toggleCompletedExpanded() } // Space on Completed
            return
        }
        toggleCompleted(selectedTaskID, closingDetail: presentedDetailID == selectedTaskID)
    }

    /// `closingDetail` is for completing from inside the details popover:
    /// once it's done, the popover has nothing left to show.
    package func toggleCompleted(_ id: String, closingDetail: Bool = false) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let done = !task.isCompleted
        guard actions.setCompleted(done, taskID: id, undo: { [weak self] in self?.toggleCompleted(id) }) else { return }
        if closingDetail && done { setPresented(nil) }

        // Stay in the old section for a moment, checked, then move.
        lingeringIDs.insert(id)
        lingerTasks[id]?.cancel()
        lingerTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.lingerDuration)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { _ = self?.lingeringIDs.remove(id) }
            self?.lingerTasks[id] = nil
        }
    }

    package func edit(_ change: TaskChange, taskID id: String) { actions.edit(change, taskID: id) }

    package func isReadOnly(_ task: TaskItem) -> Bool { actions.isReadOnly(task) }

    // MARK: - Deletion

    package func requestDeletion(of task: TaskItem) {
        actions.requestDeletion(of: task) { [weak self] in self?.forget(task.id) }
    }

    package func delete(_ id: String) {
        if actions.delete(id) { forget(id) }
    }

    /// A deleted task can't stay selected or open.
    private func forget(_ id: String) {
        if presentedDetailID == id { setPresented(nil) }
        if selectedTaskID == id { selectedTaskID = nil }
    }
}
