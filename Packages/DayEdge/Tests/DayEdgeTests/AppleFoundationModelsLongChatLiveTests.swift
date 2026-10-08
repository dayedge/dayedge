import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// A long on-device conversation over a busy (fake) calendar, once per token
/// meter: with the budget (estimate, and exact on macOS 26.4+) no reply may
/// fail; without it (`none`, how it was before) the failures are reported,
/// for comparison. Opt-in: `DAYEDGE_LIVE_APPLE_MODEL=1`.
@MainActor
final class AppleFoundationModelsLongChatLiveTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["DAYEDGE_LIVE_APPLE_MODEL"] == "1" else {
            throw XCTSkip("Set DAYEDGE_LIVE_APPLE_MODEL=1 to run the on-device model")
        }
        guard AssistantBackendResolver.appleOnDeviceAvailable else {
            throw XCTSkip("Apple's on-device model isn't available on this Mac")
        }
    }

    private let prompts = [
        "What's on my calendar today?",
        "And tomorrow?",
        "When am I free on Friday for an hour?",
        "Find my meetings with Anna this week.",
        "What about next week?",
        "Which of those is the longest?",
        "What tasks are overdue?",
        "Summarise my week in two sentences.",
        "What's on Thursday?",
        "Any meetings with Anna on Thursday?",
        "When does my day end on Friday?",
        "List everything on Monday."
    ]

    /// A hundred-odd events over a week — enough for tool results to fill the window.
    private func busyWeek() -> AssistantToolContext {
        var events: [Int: [AgendaEventModel]] = [:]
        for day in 23...30 {
            events[day] = (0..<15).map { slot in
                AssistantTestData.event(slot.isMultiple(of: 3) ? "Sync with Anna about the quarterly plan \(slot)"
                                            : "Project review for the client onboarding \(day)-\(slot)",
                                        day: day, from: (8 + slot / 2, slot.isMultiple(of: 2) ? 0 : 30),
                                        to: (8 + slot / 2, slot.isMultiple(of: 2) ? 25 : 55), place: "Room \(slot)")
            }
        }
        var context = AssistantTestData.context(events: events)
        context.showsReferences = false
        context.isCompact = true
        return context
    }

    private func failures(with choice: TokenMeterChoice) async throws -> [String] {
        #if HAS_MACOS26_SDK
        guard #available(macOS 26, *) else { return [] }
        let context = busyWeek()
        var backend = AppleFoundationModelsBackend(tools: AssistantToolbox.readOnly(context), now: context.now)
        backend.meterChoice = { choice }
        let chat = ChatSession(responder: backend, references: context.references)
        var failed: [String] = []
        for prompt in prompts {
            chat.draft = prompt
            chat.sendDraft()
            await chat.settle()
            if chat.messages.last?.isFailure == true { failed.append("\(prompt) → \(chat.messages.last?.text ?? "")") }
        }
        print("[\(TokenMeters.make(choice).name)] \(failed.count) of \(prompts.count) replies failed\n" + failed.joined(separator: "\n"))
        return failed
        #else
        return []
        #endif
    }

    func testTheBudgetedChatNeverFails() async throws {
        let failed = try await failures(with: .automatic)
        XCTAssertTrue(failed.isEmpty, failed.joined(separator: "\n"))
    }

    func testTheEstimateAloneNeverFails() async throws {
        let failed = try await failures(with: .estimate)
        XCTAssertTrue(failed.isEmpty, failed.joined(separator: "\n"))
    }

    /// Not asserted — the comparison: how it went before budgeting.
    func testWithoutABudgetForComparison() async throws {
        _ = try await failures(with: .none)
    }
}
