import XCTest
@testable import Shell
@testable import Intelligence

@MainActor
final class ChatHistoryTests: XCTestCase {
    private func session(asking question: String? = nil) async -> ChatSession {
        let session = ChatSession(responder: PlaceholderChatResponder(delay: .zero))
        if let question {
            session.start(with: question)
            await session.settle()
        }
        return session
    }

    func testTheCurrentConversationIsMadeOnceAndReused() async {
        let history = ChatHistory()
        var made = 0
        let first = history.currentOrStart { made += 1; return ChatSession() }
        let again = history.currentOrStart { made += 1; return ChatSession() }
        XCTAssertTrue(first === again)
        XCTAssertEqual(made, 1)
    }

    func testANewChatKeepsTheOldOneOnlyIfSomethingWasAsked() async {
        let history = ChatHistory()
        history.start(await session())
        history.start(await session(asking: "tomorrow?"))
        XCTAssertTrue(history.past.isEmpty, "an empty conversation isn't history")
        history.start(await session())
        XCTAssertEqual(history.past.map(\.title), ["tomorrow?"])
        XCTAssertEqual(history.current?.isEmpty, true)
    }

    func testReopeningSwapsWithTheCurrentConversation() async {
        let history = ChatHistory()
        let first = await session(asking: "first")
        history.start(first)
        history.start(await session(asking: "second"))
        history.reopen(first)
        XCTAssertTrue(history.current === first)
        XCTAssertEqual(history.past.map(\.title), ["second"])
    }

    func testTheHistoryIsBounded() async {
        let history = ChatHistory()
        for index in 0...(ChatHistory.limit + 2) { history.start(await session(asking: "q\(index)")) }
        history.start(await session())
        XCTAssertEqual(history.past.count, ChatHistory.limit)
        XCTAssertEqual(history.past.first?.title, "q\(ChatHistory.limit + 2)", "newest first")
    }
}
