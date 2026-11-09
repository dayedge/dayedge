import Foundation
import Domain

/// What a row of the Action Panel (⌘K) runs: a command, or an item of the
/// selected event's or task's right-click menu — run the way that menu runs it.
package enum ActionRow: Hashable {
    case command(PanelCommand)
    case event(EventContextMenuAction)
    case task(TaskAction)
    /// Tasks, on this Reminders list (by id).
    case taskList(String)
}

/// Where the panel was opened: the view, and the selection's whole menu
/// (both empty without a selection).
package struct ActionContext {
    package var mode: ViewMode
    package var eventActions: [EventContextMenuAction] = []
    /// The selected event's Delete asks first ("Delete Event…").
    package var eventDeletionAsks = false
    package var taskEntries: [TaskMenuEntry] = []
    /// Tasks' Overview views on offer, and the lists it can show.
    package var taskViews: [TaskSmartView] = TaskSmartView.allCases
    package var taskLists: [CalendarSource] = []

    package init(mode: ViewMode, eventActions: [EventContextMenuAction] = [],
                 eventDeletionAsks: Bool = false, taskEntries: [TaskMenuEntry] = [],
                 taskViews: [TaskSmartView] = TaskSmartView.allCases, taskLists: [CalendarSource] = []) {
        self.mode = mode
        self.eventActions = eventActions
        self.eventDeletionAsks = eventDeletionAsks
        self.taskEntries = taskEntries
        self.taskViews = taskViews
        self.taskLists = taskLists
    }
}

package struct ActionItem: Identifiable, Hashable {
    package let row: ActionRow
    package let title: String
    package let symbol: String?
    /// The command whose key does the same, for its hint.
    package var shortcut: PanelCommand?
    /// A submenu's current value (the menu's checkmark).
    package var isChecked = false
    package var isDestructive = false
    package var id: ActionRow { row }
}

/// A menu's submenu (Priority, Due Date): its choices one level down.
package struct ActionSubmenu: Hashable {
    package let title: String
    package let symbol: String?
    package let items: [ActionItem]
}

/// One line of the panel: an item, a submenu, or the menu's divider.
package enum ActionEntry: Hashable, Identifiable {
    case item(ActionItem)
    case submenu(ActionSubmenu)
    /// Its position keeps the ids apart.
    case separator(Int)

    package var id: String {
        switch self {
        case .item(let item): "item-\(item.row)"
        case .submenu(let submenu): "submenu-\(submenu.title)"
        case .separator(let index): "separator-\(index)"
        }
    }
}

/// What the Action Panel lists: the selection's right-click menu first
/// (order, submenus, dividers, checkmarks), then — below a separator — what
/// can always be done here. A query matches titles plainly (no parsing),
/// flattens submenus into "Priority: High" items, and reaches each Tasks
/// list ("Show List: Work") — too many to list unasked.
package enum PanelActionList {
    package static func entries(in context: ActionContext, matching query: String) -> [ActionEntry] {
        let selection = contextual(context)
        let always = general(context).map(ActionEntry.item)
        let all = selection.isEmpty ? always : selection + [.separator(-1)] + always
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return all }
        return (flattened(all) + listItems(context.taskLists)).filter { $0.title.localizedStandardContains(words) }
            .map(ActionEntry.item)
    }

    /// A submenu's choices for a query (all of them for none).
    package static func items(of submenu: ActionSubmenu, matching query: String) -> [ActionItem] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? submenu.items : submenu.items.filter { $0.title.localizedStandardContains(words) }
    }

    private static func flattened(_ entries: [ActionEntry]) -> [ActionItem] {
        entries.flatMap { entry -> [ActionItem] in
            switch entry {
            case .item(let item): [item]
            case .separator: []
            case .submenu(let submenu):
                submenu.items.map { choice in
                    ActionItem(row: choice.row,
                               title: L10n.tr("panelactionlist.submenu.choice", "\(submenu.title): \(choice.title)"),
                               symbol: submenu.symbol, shortcut: choice.shortcut, isChecked: choice.isChecked)
                }
            }
        }
    }

    private static func contextual(_ context: ActionContext) -> [ActionEntry] {
        if !context.eventActions.isEmpty {
            return context.eventActions.enumerated().map { index, action in
                guard action != .divider else { return .separator(index) }
                return .item(ActionItem(row: .event(action),
                                        title: EventContextMenuPlan.title(for: action, deletionAsks: context.eventDeletionAsks),
                                        symbol: action.symbolName, shortcut: action.shortcut.map(PanelCommand.action),
                                        isDestructive: action.isDestructive))
            }
        }
        return context.taskEntries.enumerated().map { index, entry in
            switch entry {
            case .action(let action):
                return .item(taskItem(action))
            case .submenu(let title, let symbol, let actions, let checked):
                return .submenu(ActionSubmenu(title: title, symbol: symbol, items: actions.map { action in
                    var item = taskItem(action)
                    item.isChecked = action == checked
                    return item
                }))
            case .divider:
                return .separator(index)
            }
        }
    }

    private static func taskItem(_ action: TaskAction) -> ActionItem {
        ActionItem(row: .task(action), title: TaskContextMenuPlan.title(for: action), symbol: action.symbolName,
                   shortcut: action == .complete ? .action(.completeSelectedTask) : nil, isDestructive: action == .delete)
    }

    private static func listItems(_ lists: [CalendarSource]) -> [ActionItem] {
        lists.map { list in
            ActionItem(row: .taskList(list.id), title: L10n.tr("panelactionlist.show.list", "Show List: \(list.title)"),
                       symbol: "list.bullet")
        }
    }

    private static func general(_ context: ActionContext) -> [ActionItem] {
        let mode = context.mode
        // Ask has no date to go to.
        let today: [PanelCommand] = mode == .ask ? [] : [.action(.today)]
        let views = ViewMode.allCases.filter { $0 != mode }.map(PanelCommand.viewMode)
        // Arranging the list in view (its sort menu is by the Tasks title).
        let arrange: [PanelCommand] = mode == .tasks ? [.action(.openSortMenu)] : []
        let taskViews = context.taskViews.map(PanelCommand.taskView)
        let commands: [PanelCommand] = [.action(.newEvent), .action(.newTask)] + today + arrange + views + taskViews
            + [.action(.newChat), .action(.openSettings)]
        return commands.map { ActionItem(row: .command($0), title: $0.title, symbol: $0.symbolName, shortcut: $0) }
    }
}
