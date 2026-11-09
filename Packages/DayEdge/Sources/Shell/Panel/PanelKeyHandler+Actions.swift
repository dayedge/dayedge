import SwiftUI
import Domain
import UI
import Tasks
import Intelligence

// MARK: - Actions (⌘K)

extension PanelKeyHandler {
    /// Where the panel opens: the view, and the right-click menu of what's
    /// selected — while search shows, the result highlighted there (none:
    /// only the general commands); else the event in Month or Day, the task
    /// in its view — whole, submenus and dividers included.
    var actionContext: ActionContext {
        let mode = agendaNavigation.selectedViewMode
        var context = ActionContext(mode: mode, taskViews: taskStore.smartViews, taskLists: taskStore.shownLists)
        switch actionTarget {
        case .event(let event, let inSearch):
            context.eventActions = models.eventActions.menuActions(for: event, inSearch: inSearch != nil)
            context.eventDeletionAsks = models.eventActions.deletionAsks(event)
        case .task(let task, let place):
            context.taskEntries = TaskContextMenuPlan.entries(for: task, isReadOnly: taskStore.actions.isReadOnly(task),
                                                              context: place.menu)
        case nil:
            break
        }
        return context
    }

    /// Runs a row as its menu or key would, then closes the list.
    func run(_ row: ActionRow) {
        isActionsPresented?.wrappedValue = false
        switch row {
        case .command(.viewMode(let mode)):
            models.router.selectViewMode(mode)
        case .command(.taskView(let view)):
            models.router.showTasks(view)
        case .taskList(let id):
            models.router.showTaskList(id)
        case .command(.action(let action)):
            _ = handleShortcutAction(action)
        case .event(let action):
            guard case .event(let event, let inSearch)? = actionTarget else { return }
            // Search's Show in Calendar is its Tab.
            if action == .showInCalendar, let inSearch {
                router.showSearchResult(inSearch)
            } else {
                models.eventActions.perform(action, for: event)
            }
        case .task(let action):
            if case .task(let task, let place)? = actionTarget { perform(action, on: task, in: place) }
        }
    }

    /// What the Actions list's menu is about.
    private enum ActionTarget {
        /// A search result's carries it, for its Show in Calendar.
        case event(AgendaEventModel, inSearch: SearchResultRowItem?)
        case task(TaskItem, TaskPlace)
    }

    /// Where a task is shown: its menu there, and how its actions run.
    private enum TaskPlace {
        case tasks
        case calendar
        /// A search result, on its day (undated: none).
        case search(day: Date?)

        var menu: TaskContextMenuPlan.Context {
            if case .tasks = self { return .tasks }
            return .calendar
        }
    }

    /// While search shows (palette or Search view), its highlighted result;
    /// otherwise the view's selection.
    private var actionTarget: ActionTarget? {
        guard router.isSearchExpanded || searchPalette.isResultsViewShown else {
            if let event = selectedEvent { return .event(event, inSearch: nil) }
            return selectedTask.map(ActionTarget.task)
        }
        guard let item = searchPalette.highlightedResult else { return nil }
        switch item.result {
        case .event(let event):
            return .event(event, inSearch: item)
        case .task(let task):
            return .task(taskStore.actions.task(task.id) ?? task, .search(day: item.day))
        }
    }

    /// A task action exactly as that view's right-click menu runs it: the
    /// Tasks view through its store (completing closes its details, a delete
    /// forgets the selection); a calendar view completes through the row's
    /// own completion (as Space does), a search result toggles it as its
    /// row does; the rest through the task actions.
    private func perform(_ action: TaskAction, on task: TaskItem, in place: TaskPlace) {
        let actions = taskStore.actions
        switch place {
        case .tasks:
            taskStore.perform(action, on: task)
        case .calendar where action == .complete:
            taskCompletionRequest.wrappedValue = TaskCompletionRequest()
        case .calendar:
            actions.perform(action, on: task, day: models.calendarTasks.selection?.date)
        case .search where action == .complete:
            _ = actions.setCompleted(!task.isCompleted, taskID: task.id)
        case .search(let day):
            actions.perform(action, on: task, day: day)
        }
    }

    /// The event selected in Month or Day, as it is now.
    var selectedEvent: AgendaEventModel? {
        let mode = agendaNavigation.selectedViewMode
        guard mode == .month || mode == .day, let selection = models.eventDetail.keyboardSelectedEvent else { return nil }
        return selection.current(in: models.dataProvider.events(for: selection.date, calendar: .autoupdatingCurrent))
    }

    /// The task selected in its view, and where.
    private var selectedTask: (TaskItem, TaskPlace)? {
        let actions = taskStore.actions
        switch agendaNavigation.selectedViewMode {
        case .tasks:
            return taskStore.selectedTaskID.flatMap(actions.task).map { ($0, .tasks) }
        case .month, .day:
            return models.calendarTasks.selection.flatMap { actions.task($0.taskID) }.map { ($0, .calendar) }
        case .ask:
            return nil
        }
    }
}
