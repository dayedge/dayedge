import Foundation
import Observation
import SwiftUI
import Domain
import Intelligence

/// Ask's conversations: which one is open, how each is made (its own
/// object handles, approvals, and the tools and model Settings chooses
/// now), and how the events its answers reference are looked up.
@MainActor
@Observable
final class ChatCoordinator {
    let history = ChatHistory()
    /// A chat was picked from the footer's list: the pill names it until
    /// a new chat starts ("All Chats" otherwise).
    private(set) var isChatPicked = false

    /// Settings → Intelligence: which model answers Ask.
    @ObservationIgnored private let settings: AssistantSettingsStore
    /// What Ask's tools read: this popover's own calendar and task
    /// data. Each conversation gets its own tools (and object handles).
    @ObservationIgnored private let toolContext: AssistantToolContext
    @ObservationIgnored private let resolve: (AssistantToolContext, AssistantSettings) -> ChatResponding
    /// How Chat finds an event occurrence it references (the same cached
    /// provider the calendar reads).
    @ObservationIgnored let eventLookup: (_ id: String, _ day: Date) -> AgendaEventModel?

    init(settings: AssistantSettingsStore,
         toolContext: AssistantToolContext,
         events: @escaping (Date) -> [AgendaEventModel],
         resolve: @escaping (AssistantToolContext, AssistantSettings) -> ChatResponding = {
             AssistantBackendResolver.resolve(toolContext: $0, settings: $1)
         }) {
        self.settings = settings
        self.toolContext = toolContext
        self.resolve = resolve
        let cache = ChatEventCache(load: events)
        let calendar = toolContext.calendar
        self.eventLookup = { id, day in cache.event(id, on: calendar.startOfDay(for: day)) }
    }

    var current: ChatSession? { history.current }

    /// The footer pill's name.
    var footerLabel: String {
        isChatPicked ? (history.current?.title ?? L10n.tr("chatcoordinator.new.chat", "New Chat")) : L10n.tr("chatcoordinator.all.chats", "All Chats")
    }

    /// Ask needs its conversation to exist before it's shown.
    func ensureConversation() {
        _ = history.currentOrStart(makeSession)
    }

    /// A fresh conversation, answered by whatever Settings chooses now.
    func makeSession() -> ChatSession {
        let references = ChatReferenceRegistry()
        let approvals = ChatApprovals()
        configure(approvals)
        return ChatSession(responder: responder(references: references, approvals: approvals),
                           references: references, approvals: approvals)
    }

    /// Makes `session` the open conversation (Search → Ask).
    func start(_ session: ChatSession) {
        history.start(session)
        isChatPicked = false
    }

    /// New chat: back to the empty state; the finished conversation goes
    /// to the history.
    func newChat(animation: Animation?) {
        isChatPicked = false
        withAnimation(animation) { history.start(makeSession()) }
    }

    /// Continues an earlier conversation, with the model Settings chooses now.
    func reopen(_ session: ChatSession, animation: Animation?) {
        session.responder = responder(references: session.references, approvals: session.approvals)
        isChatPicked = true
        withAnimation(animation) { history.reopen(session) }
    }

    /// The open conversation continues with the newly chosen model.
    func settingsDidChange() {
        guard let chat = history.current else { return }
        chat.responder = responder(references: chat.references, approvals: chat.approvals)
    }

    /// "Always Allow …" lives in Settings → Intelligence.
    private func configure(_ approvals: ChatApprovals) {
        approvals.isAlwaysAllowed = { [settings] kind in settings.settings.alwaysAllowed.contains(kind) }
        approvals.rememberAlwaysAllowed = { [settings] kind in
            settings.update { $0.alwaysAllowed.insert(kind) }
        }
    }

    /// Who answers a conversation: whatever Settings → Intelligence says
    /// now, with tools that mint handles into the conversation's registry.
    private func responder(references: ChatReferenceRegistry, approvals: ChatApprovals) -> ChatResponding {
        var context = toolContext
        context.references = references
        context.approvals = approvals
        return resolve(context, settings.settings)
    }
}
