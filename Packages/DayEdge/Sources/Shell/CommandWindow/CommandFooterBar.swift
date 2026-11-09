import SwiftUI
import Domain
import UI
import Intelligence

/// The Command Window's one bottom row, kept quiet: the view's selector
/// (calendars in Month and Day, lists in Tasks, chats in Ask — none in the
/// Search view), then Actions (⌘K) — which also switches views and opens
/// Settings. No key hints: the keys are in Actions and the menus. The
/// popover's footer controls and pickers.
struct CommandFooterBar: View {
    let models: RootModels
    @Binding var isSelectorPresented: Bool
    @Binding var isActionsPresented: Bool
    let keyHandler: PanelKeyHandler
    let indexActivity: CalendarIndexActivity?
    let onOpenSettings: (SettingsDestination?) -> Void

    private var mode: ViewMode { models.agendaNavigation.selectedViewMode }
    private var isSearchViewShown: Bool { models.searchPalette.isResultsViewShown }

    var body: some View {
        HStack(spacing: 8) {
            selector
            Spacer(minLength: 0)
            ActionsChromeButton(isPresented: $isActionsPresented) {
                ActionsListView(entries: { PanelActionList.entries(in: keyHandler.actionContext, matching: $0) },
                                onRun: { keyHandler.run($0) },
                                onClose: { _ = keyHandler.handleShortcutAction(.showActions) })
                    .frame(width: 340)
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var selector: some View {
        if isSearchViewShown {
            BottomContextSelector(label: nil, symbol: "calendar", isPresented: $isSelectorPresented,
                                  indexActivity: indexActivity, picker: { EmptyView() })
        } else {
            switch mode {
            case .tasks:
                BottomContextSelector(label: models.taskStore.listVisibility.summaryLabel, symbol: "checklist",
                                      isPresented: $isSelectorPresented, indexActivity: indexActivity) {
                    TaskListSelectorPicker(taskStore: models.taskStore, onOpenSettings: onOpenSettings)
                }
            case .ask:
                BottomContextSelector(label: models.chat.footerLabel, symbol: "bubble.left",
                                      isPresented: $isSelectorPresented, indexActivity: indexActivity) {
                    ChatSelectorPicker(chat: models.chat)
                }
            case .month, .day:
                BottomContextSelector(label: models.visibilityStore.summaryLabel, symbol: "calendar",
                                      isPresented: $isSelectorPresented, indexActivity: indexActivity) {
                    CalendarSelectorPicker(visibilityStore: models.visibilityStore, onOpenSettings: onOpenSettings)
                }
            }
        }
    }
}
