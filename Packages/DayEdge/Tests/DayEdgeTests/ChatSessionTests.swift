import XCTest
@testable import Shell
@testable import Intelligence

@MainActor
final class ChatSessionTests: XCTestCase {
    private func session(answer: String = "Hi") -> ChatSession {
        ChatSession(responder: PlaceholderChatResponder(delay: .zero, answer: answer))
    }

    func testTheQueryBecomesTheFirstMessageAndAReplyIsPending() {
        let chat = session()
        chat.start(with: "  hallo ")
        XCTAssertEqual(chat.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(chat.messages[0].text, "hallo")
        XCTAssertTrue(chat.messages[1].isPending)
        XCTAssertTrue(chat.isResponding)
    }

    func testTheReplyReplacesThinking() async {
        let chat = session(answer: "Hi — how can I help?")
        chat.start(with: "hallo")
        await chat.settle()
        XCTAssertFalse(chat.messages[1].isPending)
        XCTAssertEqual(chat.messages[1].text, "Hi — how can I help?")
        XCTAssertFalse(chat.isResponding)
    }

    func testSendingNeedsTextAndNoReplyInFlight() async {
        let chat = session()
        XCTAssertFalse(chat.canSend)
        chat.draft = "   "
        XCTAssertFalse(chat.canSend)
        chat.draft = "next"
        chat.start(with: "hallo")
        XCTAssertFalse(chat.canSend, "wait for the reply")
        await chat.settle()
        XCTAssertTrue(chat.canSend)
        chat.sendDraft()
        XCTAssertEqual(chat.draft, "")
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.map(\.text), ["hallo", "next"])
    }

    func testEachReplyUpdateReplacesTheTextSoFar() async {
        let chat = ChatSession(responder: SnapshotResponder(snapshots: ["Let me", "Let me check…", "You have a dentist at 8."]))
        chat.start(with: "tomorrow?")
        await chat.settle()
        XCTAssertEqual(chat.messages.last?.text, "You have a dentist at 8.", "an answer that starts over replaces, never appends")
    }

    func testReplyReferencesBecomeTypedPartsAndPartialTokensNeverShow() async {
        let references = ChatReferenceRegistry()
        let day = Date(timeIntervalSinceReferenceDate: 0)
        let daily = ChatEventReference(id: "ev-daily", day: day, snapshot: .init(title: "Daily"))
        XCTAssertEqual(references.handle(for: .event(daily)), "E1")
        let recorder = PartsRecorder()
        let chat = ChatSession(
            responder: SnapshotResponder(snapshots: ["Friday:", "Friday:\n[[E", "Friday:\n[[E1]]"]),
            references: references
        )
        recorder.watch(chat)
        chat.start(with: "friday?")
        await chat.settle()

        XCTAssertEqual(chat.messages.last?.parts, [.text("Friday:"), .event(daily)])
        XCTAssertEqual(chat.messages.last?.text, "Friday:\n[[E1]]", "the raw text stays for the model's history")
        XCTAssertFalse(recorder.sawRawToken, "a half-streamed token never reaches the screen")
    }

    func testASwappedResponderAnswersTheNextMessageAndHistoryStays() async {
        let chat = ChatSession(responder: PlaceholderChatResponder(delay: .zero, answer: "from the first model"))
        chat.start(with: "one")
        await chat.settle()
        chat.responder = PlaceholderChatResponder(delay: .zero, answer: "from the second model")
        chat.draft = "two"
        chat.sendDraft()
        await chat.settle()
        XCTAssertEqual(chat.messages.map(\.text), ["one", "from the first model", "two", "from the second model"])
    }

    func testCancellingStopsTheReply() async {
        let chat = ChatSession(responder: PlaceholderChatResponder(delay: .seconds(10)))
        chat.start(with: "hallo")
        chat.cancel()
        XCTAssertFalse(chat.isResponding)
        XCTAssertEqual(chat.messages.last?.text, "")
    }
}

private struct SnapshotResponder: ChatResponding {
    let snapshots: [String]

    func reply(to conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            snapshots.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

/// Records whether any shown text part ever contained a raw token.
@MainActor
private final class PartsRecorder {
    private(set) var sawRawToken = false

    func watch(_ chat: ChatSession) {
        withObservationTracking {
            for message in chat.messages {
                for case .text(let text) in message.parts where text.contains("[[") { sawRawToken = true }
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.watch(chat) }
        }
    }
}

@MainActor
final class ChatSessionStopTests: XCTestCase {
    func testStoppingBeforeAnyTextRemovesTheEmptyAnswer() {
        let chat = ChatSession(responder: PlaceholderChatResponder(delay: .seconds(10)))
        chat.start(with: "hallo")
        chat.stop()
        XCTAssertFalse(chat.isResponding)
        XCTAssertEqual(chat.messages.map(\.text), ["hallo"], "the question stays; the unstarted answer goes")
        chat.draft = "again"
        XCTAssertTrue(chat.canSend)
    }

    func testStoppingKeepsWhatWasWrittenSoFar() async throws {
        let chat = ChatSession(responder: SlowSnapshots())
        chat.start(with: "tell me")
        try await Task.sleep(for: .milliseconds(80))
        chat.stop()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(chat.messages.last?.text, "Partial", "later pieces never arrive")
        XCTAssertEqual(chat.messages.last?.isPending, false)
    }
}

/// "Partial" at once, the rest much later.
private struct SlowSnapshots: ChatResponding {
    func reply(to conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield("Partial")
                try? await Task.sleep(for: .milliseconds(100))
                continuation.yield("Partial and more")
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
