import XCTest
@testable import Shell
@testable import Intelligence

@MainActor
final class AssistantBackendResolverTests: XCTestCase {
    private let openRouter = AssistantSettings(
        activeProvider: .openRouter,
        providers: [.openRouter: ProviderConfiguration(apiKey: "not-a-real-key", modelID: "openai/gpt-5.6-luna")]
    )

    func testLocalOnlyByDefault() {
        XCTAssertEqual(AssistantBackendResolver.choice(settings: .localOnly, appleAvailable: true), .appleOnDevice)
        XCTAssertEqual(AssistantBackendResolver.choice(settings: .localOnly, appleAvailable: false), .unavailable)
    }

    func testAChosenCompleteProviderIsUsed() {
        XCTAssertEqual(AssistantBackendResolver.choice(settings: openRouter, appleAvailable: true, remoteModelsBuilt: true), .provider(.openRouter))
        XCTAssertEqual(AssistantBackendResolver.choice(settings: openRouter, appleAvailable: true, remoteModelsBuilt: false), .appleOnDevice,
                       "a build without Tachikoma can't use it")
    }

    func testAKeyAloneNeverSwitchesAwayFromOnDevice() {
        var settings = openRouter
        settings.activeProvider = nil // a stored key, but "On this Mac" chosen
        XCTAssertEqual(AssistantBackendResolver.choice(settings: settings, appleAvailable: true, remoteModelsBuilt: true), .appleOnDevice)
    }

    func testAnIncompleteProviderExplainsWhatsMissing() async {
        let noKey = AssistantSettings(activeProvider: .openRouter)
        XCTAssertEqual(AssistantBackendResolver.choice(settings: noKey, appleAvailable: false), .unavailable)
        let chat = ChatSession(responder: AssistantBackendResolver.resolve(
            toolContext: AssistantTestData.context(), settings: noKey, appleAvailable: false
        ))
        chat.start(with: "hallo")
        await chat.settle()
        XCTAssertEqual(chat.messages.last?.text, "Add your OpenRouter API key in Settings → Intelligence.")

        XCTAssertTrue(UnavailableChatResponder.explaining(.localOnly).reason.contains("Settings → Intelligence"))
    }

    #if canImport(Tachikoma)
    func testTheProviderGetsItsModelTheFullPromptAndReferencedTools() async throws {
        let context = AssistantTestData.context(events: [24: [AssistantTestData.event("Dentist", day: 24, from: (8, 0), to: (9, 0))]])
        let backend = try XCTUnwrap(AssistantBackendResolver.resolve(toolContext: context, settings: openRouter, appleAvailable: true) as? TachikomaBackend)
        if case .openRouter(let modelID) = backend.model {
            XCTAssertEqual(modelID, "openai/gpt-5.6-luna")
        } else {
            XCTFail("expected an OpenRouter model")
        }
        XCTAssertTrue(backend.instructions(Date()).contains("write its reference alone on its own line"))
        let agenda = try await XCTUnwrap(backend.tools.first { $0.name == "get_agenda" }).call(AssistantToolArguments(["when": .string("tomorrow")]))
        XCTAssertTrue(agenda.contains("[[E1]] event 08:00–09:00 Dentist"), agenda)
    }
    #endif

    #if HAS_MACOS26_SDK
    func testOnDeviceGetsTheShortPromptAndPlainTools() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
        let context = AssistantTestData.context(events: [24: [AssistantTestData.event("Dentist", day: 24, from: (8, 0), to: (9, 0))]])
        let backend = try XCTUnwrap(AssistantBackendResolver.resolve(toolContext: context, settings: .localOnly, appleAvailable: true) as? AppleFoundationModelsBackend)
        XCTAssertFalse(backend.instructions(Date()).contains("[["), "no reference contract for the small model")
        let agenda = try await XCTUnwrap(backend.tools.first { $0.name == "get_agenda" }).call(AssistantToolArguments(["when": .string("tomorrow")]))
        XCTAssertTrue(agenda.hasSuffix("- event 08:00–09:00 Dentist · Work"), agenda)
        XCTAssertFalse(agenda.contains("[["))
    }
    #endif
}
