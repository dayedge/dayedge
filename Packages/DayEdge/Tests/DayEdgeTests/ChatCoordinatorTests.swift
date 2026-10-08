import XCTest
@testable import Shell
@testable import Intelligence

@MainActor
final class ChatCoordinatorTests: XCTestCase {
    private var resolved = 0

    private func makeCoordinator() -> ChatCoordinator {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return ChatCoordinator(
            settings: AssistantSettingsStore(fileURL: file),
            toolContext: AssistantTestData.context(),
            events: { _ in [] },
            resolve: { [unowned self] _, _ in
                resolved += 1
                return PlaceholderChatResponder(delay: .zero)
            }
        )
    }

    private func asked(_ question: String, in chat: ChatCoordinator) async -> ChatSession {
        let session = chat.makeSession()
        session.start(with: question)
        await session.settle()
        return session
    }

    func testTheConversationIsMadeOnceBeforeAskShows() {
        let chat = makeCoordinator()
        XCTAssertNil(chat.current)
        chat.ensureConversation()
        let first = chat.current
        chat.ensureConversation()
        XCTAssertNotNil(first)
        XCTAssertTrue(chat.current === first)
        XCTAssertEqual(resolved, 1)
    }

    func testFooterNamesAPickedChatUntilANewOneStarts() async {
        let chat = makeCoordinator()
        let first = await asked("lunch?", in: chat)
        chat.start(first)
        XCTAssertEqual(chat.footerLabel, "All Chats")

        chat.start(await asked("tomorrow?", in: chat))
        chat.reopen(first, animation: nil)
        XCTAssertTrue(chat.current === first)
        XCTAssertEqual(chat.footerLabel, "lunch?")
        XCTAssertEqual(chat.history.past.map(\.title), ["tomorrow?"])

        chat.newChat(animation: nil)
        XCTAssertEqual(chat.footerLabel, "All Chats")
        XCTAssertEqual(chat.current?.isEmpty, true)
        XCTAssertEqual(chat.history.past.map(\.title), ["lunch?", "tomorrow?"])
    }

    func testReopeningAndSettingsChangesTakeTheModelChosenNow() async {
        let chat = makeCoordinator()
        let first = await asked("first", in: chat)
        chat.start(first)
        chat.start(await asked("second", in: chat))

        let before = resolved
        chat.reopen(first, animation: nil)
        XCTAssertEqual(resolved, before + 1)
        chat.settingsDidChange()
        XCTAssertEqual(resolved, before + 2)
    }

    func testSettingsChangeWithoutAConversationMakesNone() {
        let chat = makeCoordinator()
        chat.settingsDidChange()
        XCTAssertNil(chat.current)
        XCTAssertEqual(resolved, 0)
    }
}
