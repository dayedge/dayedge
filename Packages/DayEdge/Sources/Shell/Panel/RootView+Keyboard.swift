import SwiftUI

extension RootView {
    /// The popover's keys: the shared handler over this root's own state.
    var keyHandler: PanelKeyHandler {
        PanelKeyHandler(models: models,
                        verticalNavigationRequest: $verticalNavigationRequest,
                        taskCompletionRequest: $taskCompletionRequest,
                        isSearchFocused: $isSearchFocused,
                        isSelectorPresented: $isSelectorPresented,
                        isActionsPresented: nil,
                        openSettings: { onOpenSettings(nil) })
    }
}
