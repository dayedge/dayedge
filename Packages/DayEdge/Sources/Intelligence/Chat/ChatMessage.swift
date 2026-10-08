import Foundation

/// One turn in an Ask conversation. A plain value: the session
/// owns the list, views only draw it, and a future backend reads it as
/// context.
package struct ChatMessage: Identifiable, Equatable, Sendable {
    package enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    package let id: UUID
    package let role: Role
    /// The raw text — what the model wrote, reference tokens included; also
    /// what's sent back to it as history.
    package var text: String
    /// What's shown: prose and the objects it references, in order.
    package var parts: [ChatContentPart]
    /// An assistant reply that hasn't produced any text yet ("thinking").
    package var isPending: Bool
    /// When it was written — a conversation can go on for days, and the
    /// model must know which day each turn's "today" meant.
    package let sentAt: Date
    /// Changes made while answering (approved, declined, undone) — shown
    /// above the reply; the model learned of them from the tool results.
    package var changes: [ChatChangeReceipt] = []
    /// A reply that failed — shown, but never sent back as history.
    package var isFailure = false

    package init(id: UUID = UUID(), role: Role, text: String, parts: [ChatContentPart]? = nil, isPending: Bool = false,
                 sentAt: Date = Date()) {
        self.id = id
        self.sentAt = sentAt
        self.role = role
        self.text = text
        self.parts = parts ?? (text.isEmpty ? [] : [.text(text)])
        self.isPending = isPending
    }
}
