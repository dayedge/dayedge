import XCTest
@testable import Shell
#if HAS_MACOS26_SDK
import FoundationModels
@testable import Domain
@testable import Intelligence
#endif

final class AssistantToolTests: XCTestCase {
    private func echoTool(recording box: ArgumentBox) -> AssistantTool {
        AssistantTool(
            name: "calendar_events",
            description: "Events on a day.",
            parameters: [
                .init(name: "day", kind: .string, description: "Which day", enumValues: ["today", "tomorrow"]),
                .init(name: "limit", kind: .integer, description: "At most this many", isRequired: false)
            ]
        ) { arguments in
            await box.set(arguments)
            return "Standup at 9:00"
        }
    }

    func testArgumentsParseFromAJSONObject() throws {
        let arguments = try AssistantToolArguments(json: #"{"day": "today", "limit": 3, "all": true}"#)
        XCTAssertEqual(try arguments.string("day"), "today")
        XCTAssertEqual(try arguments.number("limit"), 3)
        XCTAssertEqual(try arguments.bool("all"), true)
        XCTAssertNil(arguments.optionalString("missing"))
        XCTAssertThrowsError(try arguments.string("missing")) { error in
            XCTAssertEqual(error as? AssistantToolArgumentError, .missing("missing"))
        }
        XCTAssertThrowsError(try AssistantToolArguments(json: "[1]"))
    }

    // MARK: - Apple FoundationModels bridge (no model needed)

    func testFoundationModelsToolBridgeBuildsItsSchemaAndCallsTheTool() async throws {
        #if HAS_MACOS26_SDK
        guard #available(macOS 26, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
        let box = ArgumentBox()
        let bridged = try FoundationModelsTool(echoTool(recording: box))
        XCTAssertEqual(bridged.name, "calendar_events")
        XCTAssertEqual(bridged.description, "Events on a day.")

        let output = try await bridged.call(arguments: GeneratedContent(json: #"{"day": "tomorrow", "limit": 2}"#))

        XCTAssertEqual(output, "Standup at 9:00")
        let received = await box.value
        XCTAssertEqual(try received?.string("day"), "tomorrow")
        XCTAssertEqual(try received?.number("limit"), 2)
        #else
        throw XCTSkip("Built without the macOS 26 SDK")
        #endif
    }

    func testEveryReadOnlyToolBridgesToFoundationModelsAndAnswers() async throws {
        #if HAS_MACOS26_SDK
        guard #available(macOS 26, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
        let context = AssistantTestData.context(
            events: [24: [AssistantTestData.event("Dentist", day: 24, from: (8, 0), to: (9, 0))]],
            tasks: [TaskItem(id: "1", title: "Someday idea", listID: "home")]
        )
        let bridged = try AssistantToolbox.readOnly(context).map { try FoundationModelsTool($0) }
        XCTAssertEqual(bridged.map(\.name), ["get_current_date", "get_agenda", "find_free_time", "find_events", "event_details", "list_tasks", "task_recurrence", "get_days"])

        func call(_ name: String, _ json: String) async throws -> String {
            try await bridged.first { $0.name == name }!.call(arguments: GeneratedContent(json: json))
        }
        let agenda = try await call("get_agenda", #"{"when": "tomorrow"}"#)
        XCTAssertTrue(agenda.contains("08:00–09:00 Dentist"), agenda)
        let free = try await call("find_free_time", #"{"when": "tomorrow", "minutes": 60}"#)
        XCTAssertTrue(free.hasSuffix("Thursday 24 September 2026: 09:00–17:00"), free)
        let found = try await call("find_events", #"{"text": "dentist"}"#)
        XCTAssertTrue(found.contains("event Thu 24 Sep 08:00–09:00 Dentist"), found)
        let undated = try await call("list_tasks", #"{"filter": "undated"}"#)
        XCTAssertTrue(undated.contains("Someday idea"), undated)
        #else
        throw XCTSkip("Built without the macOS 26 SDK")
        #endif
    }

    func testFoundationModelsTranscriptCarriesInstructionsToolsAndEarlierTurns() throws {
        #if HAS_MACOS26_SDK
        guard #available(macOS 26, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
        let tool = try FoundationModelsTool(echoTool(recording: ArgumentBox()))
        let history: [ChatMessage] = [
            ChatMessage(role: .user, text: "hi"),
            ChatMessage(role: .assistant, text: "Hello!"),
            ChatMessage(role: .assistant, text: "", isPending: true)
        ]
        let transcript = AppleFoundationModelsBackend.transcript(instructions: "Be DayEdge.", tools: [tool], history: history[...])

        let kinds = transcript.map { entry -> String in
            switch entry {
            case .instructions(let instructions):
                return "instructions(\(instructions.toolDefinitions.map(\.name).joined()))"
            case .prompt: return "prompt"
            case .response: return "response"
            default: return "other"
            }
        }
        XCTAssertEqual(kinds, ["instructions(calendar_events)", "prompt", "response"], "a pending turn isn't history")
        #else
        throw XCTSkip("Built without the macOS 26 SDK")
        #endif
    }
}

private actor ArgumentBox {
    private(set) var value: AssistantToolArguments?
    func set(_ arguments: AssistantToolArguments) { value = arguments }
}
