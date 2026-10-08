import XCTest
@testable import Domain
@testable import Intelligence

/// The on-device window budget — measured with the estimate, an exact fake,
/// and the no-op meter; no model needed.
final class TokenMeterTests: XCTestCase {
    func testNoOpMeasuresNothing() async {
        let meter = NoOpTokenMeter()
        let empty = await meter.tokens(String(repeating: "word ", count: 1000))
        XCTAssertEqual(empty, 0)
        XCTAssertEqual(meter.margin, 0)
    }

    func testTheEstimateOverCountsText() async {
        let text = "Standup 09:30–09:45 · Weekly sync with Anna 11:00–12:00 · Dentist 16:00"
        let estimate = await EstimatingTokenMeter().tokens(text)
        XCTAssertGreaterThanOrEqual(estimate, text.count / 4, "English and calendar text run near four characters a token")
    }

    func testChoicesMapToMeters() {
        XCTAssertEqual(TokenMeters.make(.none).name, "none")
        XCTAssertEqual(TokenMeters.make(.estimate).name, "estimate")
        XCTAssertTrue(["model", "estimate"].contains(TokenMeters.make(.automatic).name), "exact where macOS has it")
        let defaults = UserDefaults(suiteName: "TokenMeterTests.\(UUID())")!
        XCTAssertEqual(TokenMeterChoice.stored(in: defaults), .automatic)
        defaults.set("none", forKey: TokenMeterChoice.defaultsKey)
        XCTAssertEqual(TokenMeterChoice.stored(in: defaults), .none)
        defaults.set("nonsense", forKey: TokenMeterChoice.defaultsKey)
        XCTAssertEqual(TokenMeterChoice.stored(in: defaults), .automatic)
    }
}

/// Counts every character as a token — an exact, pessimistic stand-in.
private struct CharacterMeter: TokenMeter {
    var name: String { "characters" }
    var margin: Double { 0.03 }
    func tokens(_ text: String) async -> Int { text.count }
    func tokens(instructions: String, tools: [AssistantTool]) async -> Int {
        instructions.count + tools.map(EstimatingTokenMeter.definitionLength).reduce(0, +)
    }
}

@MainActor
final class OnDeviceToolSpellingTests: XCTestCase {
    private func onDeviceTools() -> [AssistantTool] {
        var context = AssistantTestData.context()
        context.showsReferences = false
        context.isCompact = true
        context.approvals = ChatApprovals()
        context.changes = FakeChangeWriter()
        return AssistantToolbox.readOnly(context) + AssistantToolbox.changes(context)
    }

    func testTheTableMatchesTheRealTools() {
        let tools = onDeviceTools()
        XCTAssertEqual(Set(OnDeviceToolSpelling.table.keys), Set(tools.map(\.name)), "every on-device tool, and only those")
        for tool in tools {
            let spelling = OnDeviceToolSpelling.table[tool.name]
            XCTAssertEqual(Set(spelling?.parameters.keys ?? [:].keys), Set(tool.parameters.map(\.name)), tool.name)
        }
    }

    func testOnlyDescriptionsChange() {
        for tool in onDeviceTools() {
            let short = OnDeviceToolSpelling.apply(to: tool)
            XCTAssertEqual(short.name, tool.name)
            XCTAssertEqual(short.parameters.map(\.name), tool.parameters.map(\.name))
            XCTAssertEqual(short.parameters.map(\.isRequired), tool.parameters.map(\.isRequired))
            XCTAssertEqual(short.parameters.map(\.enumValues), tool.parameters.map(\.enumValues))
        }
    }

    /// A regression guard: the definitions were over half the window.
    func testTheShortSpellingStaysSmall() {
        let full = onDeviceTools().map(EstimatingTokenMeter.definitionLength).reduce(0, +)
        let short = onDeviceTools().map(OnDeviceToolSpelling.apply).map(EstimatingTokenMeter.definitionLength).reduce(0, +)
        // The schema's own structure stays; the descriptions were the rest.
        XCTAssertLessThan(short, full * 3 / 4, "full \(full), short \(short)")
        XCTAssertLessThan(EstimatingTokenMeter.estimate(short), 1_700, "estimated (high) tokens")
    }
}

final class ContextBudgetTests: XCTestCase {
    private func message(_ role: ChatMessage.Role, _ text: String) -> ChatMessage { ChatMessage(role: role, text: text) }

    private func longAnswer(_ index: Int) -> String {
        "Answer \(index). " + String(repeating: "You have a meeting at ten and a call at noon. ", count: 30)
    }

    func testTheWorstCaseFitsTheWindow() async {
        let meter = CharacterMeter()
        let budget = ContextBudget(meter: meter, contextSize: 4_096, limits: .standard)
        let history = (0..<20).flatMap { [message(.user, "Question \($0)?"), message(.assistant, longAnswer($0))] }
        let question = String(repeating: "very long question ", count: 200)
        let plan = await budget.plan(instructions: String(repeating: "i", count: 300), tools: [], history: history, question: question)

        var total = 300 + plan.question.count + plan.limits.reserve
        for kept in plan.history { total += kept.text.count }
        XCTAssertLessThanOrEqual(total, Int(4_096 * 0.97), "fixed + question + history + tool results + answer")
        XCTAssertLessThanOrEqual(plan.question.count, 300, "the question is capped")
        XCTAssertFalse(plan.history.isEmpty)
        XCTAssertEqual(plan.history.last?.text.hasPrefix("Answer 19."), true, "the newest exchange is kept")
        XCTAssertTrue(plan.history.filter { $0.role == .assistant }.allSatisfy { $0.text.count <= 120 }, "earlier answers shortened")
    }

    func testNoOpKeepsEverything() async {
        let budget = ContextBudget.make(.none, contextSize: 4_096)
        let history = (0..<20).flatMap { [message(.user, "Q\($0)"), message(.assistant, longAnswer($0))] }
        let plan = await budget.plan(instructions: "i", tools: [], history: history, question: "now?")
        XCTAssertEqual(plan.history.map(\.text), history.map(\.text))
        XCTAssertEqual(plan.limits, .unlimited)
    }

    func testFailuresAndPendingRepliesAreNeverHistory() async {
        var failed = message(.assistant, "That's too much")
        failed.isFailure = true
        let pending = ChatMessage(role: .assistant, text: "", isPending: true)
        let plan = await ContextBudget.make(.none, contextSize: 4_096)
            .plan(instructions: "", tools: [], history: [message(.user, "Hi"), failed, pending], question: "Again")
        XCTAssertEqual(plan.history.map(\.text), ["Hi"])
    }
}

final class ReplyToolGuardTests: XCTestCase {
    func testResultsAreCutAtLinesAndCallsAreCounted() async throws {
        let toolGuard = ReplyToolGuard(limits: .standard, meter: CharacterMeter())
        let busyDay = (1...60).map { "Event \($0) 09:00–10:00 in room \($0)" }.joined(separator: "\n")
        let first = try await toolGuard.run { busyDay }
        XCTAssertLessThanOrEqual(first.count, 450)
        XCTAssertTrue(first.hasSuffix(" more"), first)
        XCTAssertTrue(first.hasPrefix("Event 1 09:00"), "whole lines, from the top")
        _ = try await toolGuard.run { "short" }
        let third = try await toolGuard.run { "never run" }
        XCTAssertTrue(third.hasPrefix("That's enough data"))
    }

    func testUnlimitedPassesResultsThrough() async throws {
        let toolGuard = ReplyToolGuard(limits: .unlimited, meter: NoOpTokenMeter())
        let long = String(repeating: "x\n", count: 5_000)
        let result = try await toolGuard.run { long }
        XCTAssertEqual(result, long)
    }
}

final class OnDeviceRetryTests: XCTestCase {
    private struct Overflow: Error {}

    func testOneRetryWithoutHistoryThenTooLong() async throws {
        var attempts: [Bool] = []
        try await OnDeviceRetry.run(isOverflow: { $0 is Overflow }) { withHistory in
            attempts.append(withHistory)
            if withHistory { throw Overflow() }
        }
        XCTAssertEqual(attempts, [true, false], "the retry leaves the history out")

        do {
            try await OnDeviceRetry.run(isOverflow: { $0 is Overflow }) { _ in throw Overflow() }
            XCTFail("expected tooLong")
        } catch {
            XCTAssertEqual(error as? AssistantReplyError, .tooLong)
        }
    }

    func testOtherErrorsAreNotRetried() async {
        var attempts = 0
        do {
            try await OnDeviceRetry.run(isOverflow: { $0 is Overflow }) { _ in
                attempts += 1
                throw AssistantReplyError.busy
            }
        } catch {
            XCTAssertEqual(error as? AssistantReplyError, .busy)
        }
        XCTAssertEqual(attempts, 1)
    }
}

/// A failed reply is said plainly and never sent back as history.
@MainActor
final class ChatFailureTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        var conversations: [[ChatMessage]] = []
        var fails = true
    }

    private struct FailingOnce: ChatResponding {
        let recorder: Recorder
        func reply(to conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
            recorder.conversations.append(conversation)
            let fails = recorder.fails
            recorder.fails = false
            return AsyncThrowingStream { continuation in
                if fails { continuation.finish(throwing: AssistantReplyError.tooLong) } else {
                    continuation.yield("Fine")
                    continuation.finish()
                }
            }
        }
    }

    func testAFailureIsWordedMarkedAndLeftOut() async {
        let recorder = Recorder()
        let chat = ChatSession(responder: FailingOnce(recorder: recorder), approvals: ChatApprovals())
        chat.start(with: "Plan my week")
        await chat.settle()
        XCTAssertEqual(chat.messages.last?.isFailure, true)
        XCTAssertEqual(chat.messages.last?.text, AssistantReplyError.message(for: AssistantReplyError.tooLong))

        chat.draft = "Just Monday"
        chat.sendDraft()
        await chat.settle()
        XCTAssertEqual(recorder.conversations.last?.map(\.text), ["Plan my week", "Just Monday"], "the failure isn't history")
    }
}

#if HAS_MACOS26_SDK
import FoundationModels

/// The estimate's tool definitions are never shorter than the schema
/// FoundationModels builds from them (name, description and JSON).
@MainActor
final class EstimateCalibrationTests: XCTestCase {
    func testDefinitionsAreNotUnderEstimated() throws {
        guard #available(macOS 26, *) else { return }
        var context = AssistantTestData.context()
        context.isCompact = true
        context.approvals = ChatApprovals()
        context.changes = FakeChangeWriter()
        for full in AssistantToolbox.readOnly(context) + AssistantToolbox.changes(context) {
            for tool in [full, OnDeviceToolSpelling.apply(to: full)] {
                let schema = try JSONEncoder().encode(FoundationModelsTool(tool).parameters)
                let rendered = tool.name.count + tool.description.count + schema.count
                XCTAssertGreaterThanOrEqual(EstimatingTokenMeter.definitionLength(tool), rendered, tool.name)
            }
        }
    }
}
#endif

/// Settings shows only what the model reports.
final class OnDeviceModelInfoTests: XCTestCase {
    func testWhatTheModelReports() {
        let info = OnDeviceModelInfo.current(in: Locale(identifier: "en"))
        if let contextSize = info.contextSize { XCTAssertGreaterThan(contextSize, 0) }
        XCTAssertEqual(info.languages, info.languages.sorted { $0.localizedCompare($1) == .orderedAscending })
        XCTAssertFalse(info.languages.contains(""), "every language has a name")
    }
}
