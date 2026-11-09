import SwiftUI
import Domain
import UI
import Intelligence

extension CommandRootView {
    /// Ask: the popover's chat — its composer in the top row (where the
    /// command bar is elsewhere), the conversation under it, the chats in
    /// the footer's selector. Wider bubbles and a reading width come from
    /// the layout (`ChatTranscriptRowView`).
    @ViewBuilder
    var askWorkspace: some View {
        if let chat = models.chat.current {
            ChatView(session: chat, isPresented: isColumnShown(.ask),
                     objects: models.chatObjects) { EmptyView() }
                // One view per conversation, as in the popover.
                .id(ObjectIdentifier(chat))
                // The composer where the command bar's field is in the other views.
                .padding(.top, Self.commandBarInset - PanelToolbarMetrics.topInset)
                .padding(.horizontal, Self.commandBarInset - SearchBarView.surfaceHorizontalInset)
        }
    }
}
