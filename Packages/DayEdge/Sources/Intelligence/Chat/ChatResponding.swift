import Foundation

/// Where Ask's answers come from — the one seam a real assistant
/// plugs into. A reply is a stream of the answer's full text so far: each
/// element replaces the previous one. So a streaming backend and a one-shot
/// one look the same to `ChatSession`, and a backend whose answer restarts
/// (after a tool call) simply sends the new text.
package protocol ChatResponding: Sendable {
    /// Answers the last message of `conversation`, which ends with the
    /// user's turn.
    func reply(to conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error>
    /// Whether its words after a change can be shown. The on-device model's
    /// can't: after a declined change it often says it made it anyway
    /// (measured), so there the receipt alone answers.
    var narratesChanges: Bool { get }
}

extension ChatResponding {
    package var narratesChanges: Bool { true }
}

/// A stand-in until the assistant exists: waits briefly (so the thinking
/// state is visible), then answers with a greeting.
package struct PlaceholderChatResponder: ChatResponding {
    package var delay: Duration = .milliseconds(900)
    package var answer = L10n.tr("chatresponding.hi.how.can.i.help", "Hi — how can I help?")

    package func reply(to conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        let delay = delay
        let answer = answer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: delay)
                    continuation.yield(answer)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
