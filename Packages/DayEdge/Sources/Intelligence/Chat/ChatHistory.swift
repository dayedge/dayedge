import Foundation
import Observation

// swiftlint:disable todo - a planned feature, kept visible where it lands
/// Ask's conversations: the current one, and the earlier ones the
/// user can go back to. New chat and asking from search start a fresh
/// conversation; the previous one (if anything was asked) moves here.
///
/// TODO: persist past conversations across launches — in memory for now.
@MainActor
@Observable
package final class ChatHistory {
    // swiftlint:enable todo
    package init() {}

    package private(set) var current: ChatSession?
    /// Earlier conversations, newest first. Never includes `current`.
    package private(set) var past: [ChatSession] = []

    package static let limit = 20

    /// The current conversation, made with `make` when there's none yet.
    package func currentOrStart(_ make: () -> ChatSession) -> ChatSession {
        if let current { return current }
        let session = make()
        current = session
        return session
    }

    /// Starts `session` as the current conversation, keeping the previous
    /// one in the history when it has anything in it.
    package func start(_ session: ChatSession) {
        archiveCurrent()
        current = session
    }

    /// Goes back to an earlier conversation; the current one takes its
    /// place in the history.
    package func reopen(_ session: ChatSession) {
        guard let index = past.firstIndex(where: { $0 === session }) else { return }
        past.remove(at: index)
        archiveCurrent()
        current = session
    }

    private func archiveCurrent() {
        guard let current else { return }
        current.cancel()
        if !current.isEmpty {
            past.insert(current, at: 0)
            if past.count > Self.limit { past.removeLast(past.count - Self.limit) }
        }
        self.current = nil
    }
}
