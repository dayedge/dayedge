import Foundation
import Observation

/// One Ask conversation: its messages and the composer's draft.
/// Knows nothing about how it is shown or animated; `ChatView` draws it and
/// `ChatResponding` answers it.
@MainActor
@Observable
package final class ChatSession {
    package private(set) var messages: [ChatMessage] = []
    /// The composer's text.
    package var draft = ""
    /// A reply is on its way; the composer can't send until it lands.
    package private(set) var isResponding = false

    /// This conversation's object handles — shared with its tools, which
    /// mint them, so replies can be turned into references.
    package let references: ChatReferenceRegistry
    /// Changes waiting for the user — shared with this conversation's tools.
    package let approvals: ChatApprovals
    /// Who answers. Replaceable: a settings change applies from the next
    /// message, and the conversation so far is kept.
    @ObservationIgnored package var responder: ChatResponding
    @ObservationIgnored private var reply: Task<Void, Never>?

    /// When the conversation began — for the history list.
    package let startedAt: Date

    @ObservationIgnored private let now: () -> Date
    /// How often a streaming reply is redrawn at most.
    @ObservationIgnored package var streamInterval: Duration = .milliseconds(50)
    @ObservationIgnored private let calendar: Calendar

    package init(responder: ChatResponding = PlaceholderChatResponder(), references: ChatReferenceRegistry = ChatReferenceRegistry(),
                 approvals: ChatApprovals? = nil,
                 startedAt: Date = Date(), calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = { Date() }) {
        self.responder = responder
        self.references = references
        self.approvals = approvals ?? ChatApprovals()
        self.startedAt = startedAt
        self.calendar = calendar
        self.now = now
        self.approvals.onReceiptChange = { [weak self] receipt in self?.replace(receipt) }
    }

    /// Nothing asked yet.
    package var isEmpty: Bool { messages.isEmpty }

    /// The first question, as the conversation's name in the history.
    package var title: String? { messages.first { $0.role == .user }?.text }

    package var canSend: Bool {
        !isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Opens the conversation with the palette's query as its first message.
    package func start(with query: String) {
        send(query)
    }

    /// The composer's send: the draft becomes the next message.
    package func sendDraft() {
        guard canSend else { return }
        let text = draft
        draft = ""
        send(text)
    }

    /// Stops a reply in flight (the conversation is being left).
    package func cancel() {
        approvals.decide(.cancelled)
        reply?.cancel()
        reply = nil
        isResponding = false
    }

    /// The user stopped the answer: what was written so far stays; an answer
    /// that hadn't started goes away, so the question can simply be asked again.
    package func stop() {
        guard isResponding else { return }
        cancel()
        guard let last = messages.last, last.role == .assistant else { return }
        if last.text.isEmpty, last.changes.isEmpty {
            messages.removeLast()
        } else {
            update(last.id) { $0.isPending = false }
        }
    }

    /// Esc in the app: a waiting change is declined; otherwise the answer
    /// stops. Never anything else — Esc doesn't hide the panel.
    package func escape() {
        if approvals.pending != nil {
            approvals.decide(.deny)
        } else if isResponding {
            stop()
        }
    }

    /// Waits for the reply in flight (tests).
    package func settle() async {
        await reply?.value
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        let sentAt = now()
        messages.append(ChatMessage(role: .user, text: trimmed, sentAt: sentAt))
        // The model reads where the days change, so an earlier turn's
        // "today" is never taken for now.
        let conversation = ChatTimeline.dated(messages.filter { !$0.isFailure }, calendar: calendar)
        let answer = ChatMessage(role: .assistant, text: "", isPending: true, sentAt: sentAt)
        messages.append(answer)
        isResponding = true
        // This reply's changes land on its message.
        approvals.onReceipt = { [weak self] receipt in self?.update(answer.id) { $0.changes.append(receipt) } }

        let interval = streamInterval
        reply = Task { [weak self, responder] in
            do {
                // Each element is the whole reply so far: shown at most every
                // `interval` (parsing and redrawing per token would be
                // wasted), and the last one always.
                var unshown: String?
                var shownAt = ContinuousClock.now - interval
                for try await text in responder.reply(to: conversation) {
                    // Stopped: nothing more reaches the conversation.
                    guard !Task.isCancelled else { break }
                    if ContinuousClock.now - shownAt >= interval {
                        self?.show(text, in: answer.id)
                        shownAt = .now
                        unshown = nil
                    } else {
                        unshown = text
                    }
                }
                if let unshown, !Task.isCancelled { self?.show(unshown, in: answer.id) }
                self?.update(answer.id) { $0.isPending = false }
            } catch is CancellationError {
            } catch {
                self?.show(AssistantReplyError.message(for: error), in: answer.id)
                self?.update(answer.id) { $0.isFailure = true }
            }
            self?.isResponding = false
        }
    }

    /// The reply so far, as raw text and as prose + references.
    private func show(_ text: String, in id: UUID) {
        let references = references
        let parts = ChatContentParser.parse(text) { references.reference(for: $0) }
        let narrates = responder.narratesChanges
        update(id) { message in
            message.text = text
            // A model that can't be trusted to say what happened after a
            // change: its receipt says it instead.
            message.parts = narrates || message.changes.isEmpty ? parts : []
            message.isPending = false
        }
    }

    /// A receipt changed after the fact (Undo).
    private func replace(_ receipt: ChatChangeReceipt) {
        for index in messages.indices {
            if let position = messages[index].changes.firstIndex(where: { $0.id == receipt.id }) {
                messages[index].changes[position] = receipt
                return
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }
}
