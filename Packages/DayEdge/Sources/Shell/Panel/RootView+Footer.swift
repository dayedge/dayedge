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
                picker: {
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
            )
        } else {
            let visibilityStore = models.visibilityStore
            FooterBarView(
                label: visibilityStore.summaryLabel,
                isPresented: $isSelectorPresented,
                onSettingsTap: { onOpenSettings(nil) },
                indexActivity: indexActivity,
                picker: {
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
            )
        }
    }

    /// Ask's footer: the panel's usual one, with the chats in the pill.
    var chatFooter: some View {
        let chat = models.chat
        let animation = ChatAnimation.collapse(reduceMotion: reduceMotion)
        return FooterBarView(
            label: chat.footerLabel,
            symbol: "bubble.left",
            isPresented: $isChatSelectorPresented,
            onSettingsTap: { onOpenSettings(nil) },
            indexActivity: indexActivity,
            picker: {
                ChatSelectionPopover(history: chat.history,
                                     onNewChat: { chat.newChat(animation: animation) },
                                     onReopen: { chat.reopen($0, animation: animation) })
            }
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
