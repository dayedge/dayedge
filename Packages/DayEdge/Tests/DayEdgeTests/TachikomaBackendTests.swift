#if canImport(Tachikoma)
import Foundation
import Tachikoma
import XCTest
@testable import Shell
@testable import Intelligence

/// The Tachikoma backend end to end through `ChatSession`, against a
/// scripted provider: no network, no API keys.
@MainActor
final class TachikomaBackendTests: XCTestCase {
    private func backend(_ provider: ScriptedModelProvider, tools: [AssistantTool] = []) -> TachikomaBackend {
        TachikomaBackend(
            model: .custom(provider: provider),
            configuration: TachikomaConfiguration(apiKeys: [:]),
            tools: tools,
            instructions: { _ in "Be DayEdge." }
        )
    }

    func testChatSendsInstructionsAndHistoryAndShowsTheReply() async {
        let provider = ScriptedModelProvider(responses: [
            ProviderResponse(text: "Hi — how can I help?", finishReason: .stop)
        ])
        let chat = ChatSession(responder: backend(provider))

        chat.start(with: "hallo")
        await chat.settle()

        XCTAssertEqual(chat.messages.map(\.text), ["hallo", "Hi — how can I help?"])
        let request = try? XCTUnwrap(provider.requests.first)
        XCTAssertEqual(request?.messages.map(\.role), [.system, .user])
        XCTAssertEqual(request?.messages.map(\.plainText), ["Be DayEdge.", "hallo"])
        XCTAssertNil(request?.tools, "no tools, none offered")
    }

    func testEarlierTurnsAreSentWithTheNextQuestion() async {
        let provider = ScriptedModelProvider(responses: [
            ProviderResponse(text: "First answer", finishReason: .stop),
            ProviderResponse(text: "Second answer", finishReason: .stop)
        ])
        let chat = ChatSession(responder: backend(provider))
        chat.start(with: "one")
        await chat.settle()
        chat.draft = "two"
        chat.sendDraft()
        await chat.settle()

        XCTAssertEqual(provider.requests.last?.messages.map(\.plainText), ["Be DayEdge.", "one", "First answer", "two"])
        XCTAssertEqual(chat.messages.last?.text, "Second answer")
    }

    func testAConversationContinuedNextDayGetsTodaysDateAndAMarkedDayChange() async {
        let provider = ScriptedModelProvider(responses: [
            ProviderResponse(text: "You have the dentist tomorrow.", finishReason: .stop),
            ProviderResponse(text: "Today: nothing else.", finishReason: .stop)
        ])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let clock = TestClock(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 16))!)
        var responder = backend(provider)
        responder.now = { clock.date }
        responder.instructions = { [calendar] in AssistantInstructions.isoDay($0, calendar) }
        let chat = ChatSession(responder: responder, calendar: calendar, now: { clock.date })

        chat.start(with: "what's tomorrow?")
        await chat.settle()
        clock.date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
        chat.draft = "and today?"
        chat.sendDraft()
        await chat.settle()

        let first = provider.requests.first?.messages.map(\.plainText)
        let last = provider.requests.last?.messages.map(\.plainText) ?? []
        XCTAssertEqual(first?.first, "2026-09-30")
        XCTAssertEqual(last.first, "2026-10-01", "the instructions carry the date of this reply, not of the first")
        XCTAssertEqual(Array(last.dropFirst().prefix(2)), ["what's tomorrow?", "You have the dentist tomorrow."])
        XCTAssertTrue(last.last?.hasPrefix("[It is now ") == true, "the day change is marked")
        XCTAssertTrue(last.last?.hasSuffix("and today?") == true)
        XCTAssertEqual(chat.messages.map(\.text).filter { $0.hasPrefix("[") }, [], "the marking is only for the model")
    }

    func testToolCallIsExecutedAndItsResultReachesTheModel() async throws {
        let recorder = ToolCallRecorder()
        let weather = AssistantTool(
            name: "get_weather",
            description: "Current weather for a city.",
            parameters: [.init(name: "city", kind: .string, description: "City name")]
        ) { arguments in
            await recorder.record(try arguments.string("city"))
            return "12°C and cloudy"
        }
        let provider = ScriptedModelProvider(responses: [
            ProviderResponse(text: "", finishReason: .toolCalls, toolCalls: [
                AgentToolCall(id: "call-1", name: "get_weather", arguments: ["city": AnyAgentToolValue(string: "Oslo")])
            ]),
            ProviderResponse(text: "It's 12°C and cloudy in Oslo.", finishReason: .stop)
        ])
        let chat = ChatSession(responder: backend(provider, tools: [weather]))

        chat.start(with: "Weather in Oslo?")
        await chat.settle()

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["Oslo"], "the tool ran once, with the model's arguments")
        XCTAssertEqual(chat.messages.last?.text, "It's 12°C and cloudy in Oslo.")

        // The tool was offered with its schema…
        let offered = try XCTUnwrap(provider.requests.first?.tools?.first)
        XCTAssertEqual(offered.name, "get_weather")
        XCTAssertEqual(offered.parameters.required, ["city"])
        XCTAssertEqual(offered.parameters.properties["city"]?.type, .string)
        // …and its result went back to the model in the second request.
        let followUp = try XCTUnwrap(provider.requests.last)
        XCTAssertEqual(provider.requests.count, 2)
        let toolResults = followUp.messages.flatMap(\.content).compactMap { part -> AgentToolResult? in
            if case .toolResult(let result) = part { return result }
            return nil
        }
        XCTAssertEqual(toolResults.map(\.toolCallId), ["call-1"])
        XCTAssertEqual(toolResults.first?.result.stringValue, "12°C and cloudy")
    }

    func testTheAgendaToolAnswersTheModelWithRealData() async throws {
        let context = AssistantTestData.context(events: [24: [
            AssistantTestData.event("Dentist", day: 24, from: (8, 0), to: (9, 0))
        ]])
        let provider = ScriptedModelProvider(responses: [
            ProviderResponse(text: "", finishReason: .toolCalls, toolCalls: [
                AgentToolCall(id: "call-1", name: "get_agenda", arguments: ["when": AnyAgentToolValue(string: "tomorrow")])
            ]),
            ProviderResponse(text: "Tomorrow:\n- [[E1]] 08:00 Dentist\nThat's all.", finishReason: .stop)
        ])
        let chat = ChatSession(responder: backend(provider, tools: AssistantToolbox.readOnly(context)), references: context.references)

        chat.start(with: "What's on tomorrow?")
        await chat.settle()

        XCTAssertEqual(provider.requests.first?.tools?.map(\.name),
                       ["get_current_date", "get_agenda", "find_free_time", "find_events", "event_details", "list_tasks", "task_recurrence", "get_days"])
        let result = provider.requests.last?.messages.flatMap(\.content).compactMap { part -> String? in
            if case .toolResult(let result) = part { return result.result.stringValue }
            return nil
        }.first
        XCTAssertEqual(result, "Agenda for Thursday 24 September 2026:\n[[D1]] Thursday 24 September 2026\n[[E1]] event 08:00–09:00 Dentist · Work\n\(AssistantFormat.referenceHint)")
        XCTAssertEqual(chat.messages.last?.parts, [
            .text("Tomorrow:"),
            .event(ChatEventReference(id: "Dentist-24", day: AssistantTestData.date(24),
                                      snapshot: ChatObjectSnapshot(title: "Dentist", detail: "08:00–09:00"))),
            .text("That's all.")
        ], "the answer shows the real event, not the model's retyped line")
    }

    func testAChristmasAnswerShowsItsDaysAsNativeDates() async throws {
        let context = AssistantTestData.context(holidays: ["2026-12-24": "Wigilia", "2026-12-25": "Boże Narodzenie"])
        let provider = ScriptedModelProvider(responses: [
            ProviderResponse(text: "", finishReason: .toolCalls, toolCalls: [
                AgentToolCall(id: "call-1", name: "get_days", arguments: ["when": AnyAgentToolValue(string: "2026-12-24..2026-12-27")])
            ]),
            ProviderResponse(text: "W tym roku Święta układają się tak:\n[[D1]] [[D2]] [[D3]] [[D4]]\nTo daje cztery dni wolne.", finishReason: .stop)
        ])
        let chat = ChatSession(responder: backend(provider, tools: AssistantToolbox.readOnly(context)), references: context.references)
        chat.start(with: "Jak wypadają Święta?")
        await chat.settle()

        let parts = try XCTUnwrap(chat.messages.last?.parts)
        XCTAssertEqual(parts.first, .text("W tym roku Święta układają się tak:"))
        XCTAssertEqual(parts.last, .text("To daje cztery dni wolne."))
        let days = parts.compactMap { part -> ChatDayReference? in
            if case .day(let day) = part { return day }
            return nil
        }
        XCTAssertEqual(days.map(\.label), ["Wigilia", "Boże Narodzenie", nil, nil])
        XCTAssertEqual(ChatContentBlock.blocks(parts, calendar: AssistantTestData.calendar).count, 3, "prose, one run of four dates, prose")
    }

    func testAProviderFailureBecomesAnErrorReply() async {
        let provider = ScriptedModelProvider(responses: [])
        let chat = ChatSession(responder: backend(provider))
        chat.start(with: "hallo")
        await chat.settle()
        XCTAssertEqual(chat.messages.last?.text, "Something went wrong. Try again.")
        XCTAssertFalse(chat.isResponding)
    }

    func testToolArgumentsKeepTheirTypes() throws {
        let tool = TachikomaBackend.agentTool(AssistantTool(
            name: "t", description: "d",
            parameters: [
                .init(name: "when", kind: .string, description: "", enumValues: ["today", "tomorrow"]),
                .init(name: "limit", kind: .integer, description: "", isRequired: false)
            ]
        ) { _ in "" })
        XCTAssertEqual(tool.parameters.required, ["when"])
        XCTAssertEqual(tool.parameters.properties["when"]?.enumValues, ["today", "tomorrow"])
        XCTAssertEqual(tool.parameters.properties["limit"]?.type, .integer)
    }
}

/// Answers each request with the next scripted response and records what
/// it was asked. Its model id has no "/", so Tachikoma uses it as-is.
private final class TestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

private final class ScriptedModelProvider: ModelProvider, @unchecked Sendable {
    let modelId = "scripted"
    let baseURL: String? = nil
    let apiKey: String? = nil
    let capabilities = ModelCapabilities(supportsTools: true, supportsStreaming: false)

    private let lock = NSLock()
    private var remaining: [ProviderResponse]
    private var recorded: [ProviderRequest] = []

    init(responses: [ProviderResponse]) {
        remaining = responses
    }

    var requests: [ProviderRequest] { lock.withLock { recorded } }

    func generateText(request: ProviderRequest) async throws -> ProviderResponse {
        try lock.withLock {
            recorded.append(request)
            guard !remaining.isEmpty else { throw ScriptError.exhausted }
            return remaining.removeFirst()
        }
    }

    func streamText(request: ProviderRequest) async throws -> AsyncThrowingStream<TextStreamDelta, Error> {
        throw ScriptError.exhausted
    }

    enum ScriptError: Error { case exhausted }
}

private actor ToolCallRecorder {
    private(set) var calls: [String] = []
    func record(_ city: String) { calls.append(city) }
}

private extension ModelMessage {
    var plainText: String {
        content.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined()
    }
}
#endif
