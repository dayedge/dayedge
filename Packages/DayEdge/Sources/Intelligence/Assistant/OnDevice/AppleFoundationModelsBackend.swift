#if HAS_MACOS26_SDK
import Foundation
import FoundationModels

/// Apple's on-device model through `LanguageModelSession`. The framework
/// runs tools itself and streams the answer; it exposes no reasoning.
///
/// Stateless per reply: the session is rebuilt from the conversation each
/// time, so `ChatSession` stays the one owner of history. Its 4K window is
/// budgeted (`ContextBudget`): the tools in their short spelling, the
/// question, tool results and answer capped, the history what's left — and
/// one retry without history if the meter was off. Remote models are not
/// involved.
@available(macOS 26, *)
package struct AppleFoundationModelsBackend: ChatResponding {
    package var tools: [AssistantTool] = []
    /// Built for each reply, with the date at that moment.
    package var instructions: @Sendable (Date) -> String = { AssistantInstructions.onDevice(now: $0) }
    package var now: @Sendable () -> Date = { Date() }
    /// Which meter budgets the window (hidden default, for comparing).
    package var meterChoice: @Sendable () -> TokenMeterChoice = { .stored() }
    package var narratesChanges: Bool { false }

    /// On a Mac that supports Apple Intelligence, with it turned on and the
    /// model downloaded.
    package static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    package static var status: OnDeviceModelStatus {
        switch SystemLanguageModel.default.availability {
        case .available: return .ready
        case .unavailable(.appleIntelligenceNotEnabled): return .turnedOff
        case .unavailable(.deviceNotEligible): return .unsupported
        case .unavailable(.modelNotReady): return .preparing
        @unknown default: return .unsupported
        }
    }

    package func reply(to conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        let tools = tools.map(OnDeviceToolSpelling.apply)
        let instructions = instructions(now())
        let budget = ContextBudget.make(meterChoice(), contextSize: SystemLanguageModel.default.contextSize)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let promptIndex = conversation.lastIndex(where: { $0.role == .user }) else {
                        continuation.finish()
                        return
                    }
                    let plan = await budget.plan(instructions: instructions, tools: tools, history: conversation[..<promptIndex],
                                                 question: conversation[promptIndex].text)
                    let attempt = Attempt(plan: plan, instructions: instructions, tools: tools, meter: budget.meter)
                    try await OnDeviceRetry.run(isOverflow: Self.isOverflow) { withHistory in
                        try await attempt.stream(withHistory: withHistory, into: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.translated(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One reply's inputs, tried with history and — once, if it overflows —
    /// without.
    private struct Attempt {
        let plan: ContextBudget.Plan
        let instructions: String
        let tools: [AssistantTool]
        let meter: any TokenMeter

        /// Snapshots are the answer so far: before calling a tool the model
        /// emits an empty response, rendered "null"; the answer after the
        /// tool starts over, and replaces it (a retry, likewise).
        func stream(withHistory: Bool, into continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
            let toolGuard = ReplyToolGuard(limits: plan.limits, meter: meter)
            let adapted = try tools.map { try FoundationModelsTool($0, guard: toolGuard) }
            let session = LanguageModelSession(
                tools: adapted,
                transcript: AppleFoundationModelsBackend.transcript(instructions: instructions, tools: adapted,
                                                                    history: withHistory ? plan.history : [])
            )
            let options = GenerationOptions(maximumResponseTokens: plan.limits.answer)
            for try await snapshot in session.streamResponse(to: plan.question, options: options) {
                let content = snapshot.content
                guard !content.isEmpty, content != "null" else { continue }
                continuation.yield(content)
            }
        }
    }

    package static func transcript(instructions: String, tools: [FoundationModelsTool], history: some Collection<ChatMessage>) -> Transcript {
        var entries: [Transcript.Entry] = [.instructions(Transcript.Instructions(
            segments: [.text(.init(content: instructions))],
            toolDefinitions: tools.map { Transcript.ToolDefinition(tool: $0) }
        ))]
        for message in history where message.carriesContext {
            let segments: [Transcript.Segment] = [.text(.init(content: message.text))]
            switch message.role {
            case .user: entries.append(.prompt(Transcript.Prompt(segments: segments)))
            case .assistant: entries.append(.response(Transcript.Response(assetIDs: [], segments: segments)))
            }
        }
        return Transcript(entries: entries)
    }

    static func isOverflow(_ error: Error) -> Bool {
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error { return true }
        return false
    }

    /// The framework's errors, as ones the chat can word.
    static func translated(_ error: Error) -> Error {
        guard let generation = error as? LanguageModelSession.GenerationError else { return error }
        switch generation {
        case .exceededContextWindowSize: return AssistantReplyError.tooLong
        case .rateLimited, .concurrentRequests: return AssistantReplyError.busy
        case .assetsUnavailable: return AssistantReplyError.unavailable
        case .guardrailViolation, .refusal: return AssistantReplyError.declined
        case .unsupportedLanguageOrLocale: return AssistantReplyError.unsupportedLanguage
        default: return error
        }
    }
}

/// An `AssistantTool` as a FoundationModels `Tool`: arguments arrive as
/// `GeneratedContent` shaped by a schema built at runtime from the tool's
/// parameters.
@available(macOS 26, *)
package struct FoundationModelsTool: Tool {
    package typealias Arguments = GeneratedContent
    package typealias Output = String

    package let tool: AssistantTool
    package let parameters: GenerationSchema
    /// Keeps this reply's tool results inside the budget; nil = as they are.
    private let toolGuard: ReplyToolGuard?

    package var name: String { tool.name }
    package var description: String { tool.description }

    package init(_ tool: AssistantTool, guard toolGuard: ReplyToolGuard? = nil) throws {
        self.tool = tool
        self.toolGuard = toolGuard
        let properties = tool.parameters.map { parameter in
            DynamicGenerationSchema.Property(
                name: parameter.name,
                description: parameter.description,
                schema: Self.schema(for: parameter),
                isOptional: !parameter.isRequired
            )
        }
        parameters = try GenerationSchema(
            root: DynamicGenerationSchema(name: tool.name, description: tool.description, properties: properties),
            dependencies: []
        )
    }

    package func call(arguments: GeneratedContent) async throws -> String {
        let run: @Sendable () async throws -> String = { [tool] in try await tool.call(AssistantToolArguments(json: arguments.jsonString)) }
        guard let toolGuard else { return try await run() }
        return try await toolGuard.run(run)
    }

    private static func schema(for parameter: AssistantTool.Parameter) -> DynamicGenerationSchema {
        if let choices = parameter.enumValues {
            return DynamicGenerationSchema(name: parameter.name, anyOf: choices)
        }
        switch parameter.kind {
        case .string: return DynamicGenerationSchema(type: String.self)
        case .number: return DynamicGenerationSchema(type: Double.self)
        case .integer: return DynamicGenerationSchema(type: Int.self)
        case .boolean: return DynamicGenerationSchema(type: Bool.self)
        }
    }
}
#endif
