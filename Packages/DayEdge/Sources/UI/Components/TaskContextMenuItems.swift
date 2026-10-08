import SwiftUI
import Domain

/// A task's right-click menu, from `TaskContextMenuPlan`. Shared by every
/// view that shows a task. Native rows: a `Label` with the plan's symbol,
/// submenus' choices as text with the menu's checkmark for the current one.
package struct TaskContextMenuItems: View {
    package let task: TaskItem
    package var isReadOnly = false
    package var context: TaskContextMenuPlan.Context = .tasks
    package let perform: (TaskAction) -> Void
    /// Set on search results, where Show in Tasks is also Tab's.
    @Environment(\.searchResultReveal) private var searchResultReveal

    package var body: some View {
        Group {
            ForEach(Array(TaskContextMenuPlan.entries(for: task, isReadOnly: isReadOnly, context: context).enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .action(let action):
                    button(action)
                case .submenu(let title, let symbol, let actions, let checked):
                    Menu {
                        ForEach(actions.indices, id: \.self) { index in
                            choice(actions[index], isChecked: actions[index] == checked)
                        }
                    } label: {
                        Label(title, systemImage: symbol)
                    }
                case .divider:
                    Divider()
                }
            }
        }
        // The panel's tint would colour the symbols; a native menu draws
        // them like its text.
        .tint(nil)
    }

    private func button(_ action: TaskAction) -> some View {
        // In search, Show in Tasks is what Tab does there (the same action).
        let isSearchReveal = action == .showInTasks && searchResultReveal != nil
        return MenuRow(TaskContextMenuPlan.title(for: action), symbol: action.symbolName,
                       role: action == .delete ? .destructive : nil,
                       shortcut: isSearchReveal ? KeyboardCommands.showSearchResult.swiftUIShortcut : nil) { perform(action) }
    }

    /// A submenu choice, with the menu's checkmark on the task's current value.
    private func choice(_ action: TaskAction, isChecked: Bool) -> some View {
        Toggle(TaskContextMenuPlan.title(for: action), isOn: Binding(get: { isChecked }, set: { _ in perform(action) }))
    }

    package init(task: TaskItem, isReadOnly: Bool = false, context: TaskContextMenuPlan.Context = .tasks, perform: @escaping (TaskAction) -> Void) {
        self.task = task
        self.isReadOnly = isReadOnly
        self.context = context
        self.perform = perform
    }
}
