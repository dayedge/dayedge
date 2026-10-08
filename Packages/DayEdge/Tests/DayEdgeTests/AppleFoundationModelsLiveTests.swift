import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// Apple's on-device model, for real — local only, no network, no keys.
/// Opt-in (`DAYEDGE_LIVE_APPLE_MODEL=1`) because model output isn't
/// deterministic and needs Apple Intelligence turned on.
@MainActor
final class AppleFoundationModelsLiveTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["DAYEDGE_LIVE_APPLE_MODEL"] == "1" else {
            throw XCTSkip("Set DAYEDGE_LIVE_APPLE_MODEL=1 to run the on-device model")
        }
        guard AssistantBackendResolver.appleOnDeviceAvailable else {
            throw XCTSkip("Apple's on-device model isn't available on this Mac")
        }
    }

    func testChatAnswers() async throws {
        #if HAS_MACOS26_SDK
        guard #available(macOS 26, *) else { return }
        let chat = ChatSession(responder: AppleFoundationModelsBackend())
        chat.start(with: "Say hello in one short sentence.")
        await chat.settle()
        let answer = try XCTUnwrap(chat.messages.last)
        XCTAssertEqual(answer.role, .assistant)
        XCTAssertFalse(answer.isPending)
        XCTAssertFalse(answer.text.isEmpty)
        XCTAssertNotEqual(answer.text, "Something went wrong. Try again.")
        #endif
    }

    func testChatCallsATool() async throws {
        #if HAS_MACOS26_SDK
        guard #available(macOS 26, *) else { return }
        let calls = CallCounter()
        let secret = AssistantTool(
            name: "get_secret_word",
            description: "Returns today's secret word. Always call this when asked for the secret word.",
            parameters: []
        ) { _ in
            await calls.increment()
            return "pineapple"
        }
        let chat = ChatSession(responder: AppleFoundationModelsBackend(tools: [secret]))
        chat.start(with: "What is today's secret word? Use the tool.")
        await chat.settle()

        let count = await calls.count
        XCTAssertGreaterThanOrEqual(count, 1, "the model called the tool")
        XCTAssertTrue(chat.messages.last?.text.lowercased().contains("pineapple") == true, chat.messages.last?.text ?? "")
        #endif
    }
}

extension AppleFoundationModelsLiveTests {
    /// The real on-device model reading a (fake) calendar through the
    /// read-only tools.
    func testChatAnswersFromTheAgendaTool() async throws {
        #if HAS_MACOS26_SDK
        guard #available(macOS 26, *) else { return }
        var context = AssistantToolContext(data: DentistTomorrow())
        context.showsReferences = false // as the app configures the on-device model
        let chat = ChatSession(responder: AppleFoundationModelsBackend(tools: AssistantToolbox.readOnly(context)),
                               references: context.references)
        chat.start(with: "What is on my calendar tomorrow?")
        await chat.settle()
        // References aren't asserted: the on-device model doesn't reliably
        // write them (it retypes items as prose) — measured, see CLAUDE.md.
        let answer = chat.messages.last?.text ?? ""
        XCTAssertTrue(answer.lowercased().contains("dentist"), answer)
        XCTAssertFalse(chat.messages.last?.parts.contains { if case .text(let text) = $0 { return text.contains("[[") } else { return false } } ?? true,
                       "a raw token never shows")
        #endif
    }
}

/// One event, tomorrow at 08:00, whatever day that is.
private struct DentistTomorrow: AssistantDataSource {
    func agenda(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        guard range.start <= tomorrow, tomorrow < range.end else { return [] }
        let event = AgendaEventModel(
            startTime: "08:00", endTime: "09:00",
            startDate: tomorrow.addingTimeInterval(8 * 3600), endDate: tomorrow.addingTimeInterval(9 * 3600),
            title: "Dentist appointment", calendarName: "Personal"
        )
        return [AgendaDaySection(date: tomorrow, events: [event])]
    }

    func taskSnapshot() async -> AssistantTaskSnapshot { AssistantTaskSnapshot(tasks: [], lists: []) }

    func holidays(in range: DateInterval, calendar: Calendar) async -> AssistantHolidays { AssistantHolidays() }
}

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
