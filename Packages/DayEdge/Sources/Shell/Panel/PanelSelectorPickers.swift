import SwiftUI
import Domain
import UI
import Tasks
import Intelligence

/// The footer selector's popovers, shared by the popover and the Command
/// Window: one implementation of each, over the shared stores.

/// Month and Day: which calendars are shown.
struct CalendarSelectorPicker: View {
    let visibilityStore: SourceVisibilityStore
    let onOpenSettings: (SettingsDestination?) -> Void

    var body: some View {
        SourceSelectionPopover(
            title: L10n.tr("rootview.footer.calendars", "Calendars"),
            groups: SelectionGroups.bySource(visibilityStore.availableItems, kind: .calendar) {
                visibilityStore.isVisible($0)
            },
            emptyMessage: L10n.tr("rootview.footer.no.calendars.available", "No calendars available"),
            showAllTitle: L10n.tr("rootview.footer.show.all.calendars", "Show All Calendars"),
            manageTitle: L10n.tr("rootview.footer.manage.calendars", "Manage Calendars…"),
            canShowAll: !visibilityStore.isEverythingVisible,
            onToggle: { visibilityStore.toggle($0) },
            onSolo: { visibilityStore.solo($0, among: visibilityStore.availableItems.map(\.id)) },
            onShowAll: { visibilityStore.showAll() },
            onManage: { onOpenSettings(.calendars) }
        )
    }
}

/// Tasks: which Reminder lists are shown.
struct TaskListSelectorPicker: View {
    let taskStore: TaskStore
    let onOpenSettings: (SettingsDestination?) -> Void

    var body: some View {
        SourceSelectionPopover(
            title: L10n.tr("rootview.footer.lists", "Lists"),
            groups: taskStore.selectorGroups,
            emptyMessage: L10n.tr("rootview.footer.no.lists.available", "No lists available"),
            showAllTitle: L10n.tr("rootview.footer.show.all.lists", "Show All Lists"),
            manageTitle: L10n.tr("rootview.footer.manage.lists", "Manage Lists…"),
            canShowAll: !taskStore.listVisibility.isEverythingVisible,
            onToggle: { taskStore.toggleVisibility($0) },
            onSolo: { taskStore.solo($0) },
            onShowAll: { taskStore.listVisibility.showAll() },
            onManage: { onOpenSettings(.tasks) }
        )
    }
}

/// Ask: the conversations, and a new one.
struct ChatSelectorPicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let chat: ChatCoordinator

    var body: some View {
        let animation = ChatAnimation.collapse(reduceMotion: reduceMotion)
        ChatSelectionPopover(history: chat.history,
                             onNewChat: { chat.newChat(animation: animation) },
                             onReopen: { chat.reopen($0, animation: animation) })
    }
}
