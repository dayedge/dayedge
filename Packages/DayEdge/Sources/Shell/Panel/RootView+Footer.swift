import SwiftUI
import UI
import Intelligence

extension RootView {
    /// Each view's own footer selector, the same popover over different
    /// content: calendars in Month/Day, Reminder lists in Tasks (Ask has its
    /// chats, in its own footer), and none in the Search view — only the
    /// gear.
    @ViewBuilder
    var footerBar: some View {
        if searchPalette.isResultsViewShown {
            FooterBarView(
                label: nil,
                isPresented: $isSelectorPresented,
                onSettingsTap: { onOpenSettings(nil) },
                indexActivity: indexActivity,
                picker: { EmptyView() }
            )
        } else if agendaNavigation.selectedViewMode == .tasks {
            FooterBarView(
                label: taskStore.listVisibility.summaryLabel,
                symbol: "checklist",
                isPresented: $isSelectorPresented,
                onSettingsTap: { onOpenSettings(nil) },
                indexActivity: indexActivity,
                picker: { TaskListSelectorPicker(taskStore: taskStore, onOpenSettings: onOpenSettings) }
            )
        } else {
            FooterBarView(
                label: models.visibilityStore.summaryLabel,
                isPresented: $isSelectorPresented,
                onSettingsTap: { onOpenSettings(nil) },
                indexActivity: indexActivity,
                picker: { CalendarSelectorPicker(visibilityStore: models.visibilityStore, onOpenSettings: onOpenSettings) }
            )
        }
    }

    /// Ask's footer: the panel's usual one, with the chats in the pill.
    var chatFooter: some View {
        FooterBarView(
            label: models.chat.footerLabel,
            symbol: "bubble.left",
            isPresented: $isChatSelectorPresented,
            onSettingsTap: { onOpenSettings(nil) },
            indexActivity: indexActivity,
            picker: { ChatSelectorPicker(chat: models.chat) }
        )
    }

    /// The one view switcher, in the panel toolbar.
    var viewSwitcher: some View {
        // Folded over the field in Ask, over the open search palette and in
        // the Search view (showing the view the search started from);
        // unfolds on hover.
        ViewModeSwitcherView(selectedMode: agendaNavigation.selectedViewMode,
                             folds: isAskShown || router.isSearchExpanded || searchPalette.isResultsViewShown,
                             onSelect: { router.selectViewMode($0) })
    }
}
