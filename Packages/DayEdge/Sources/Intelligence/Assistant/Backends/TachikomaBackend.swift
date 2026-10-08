#if canImport(Tachikoma)
import Foundation
import Tachikoma

/// Remote models through Tachikoma — OpenRouter for now; OpenAI, Anthropic,
/// Ollama and LM Studio are other `LanguageModel`s through this same type.
///
/// Tachikoma runs the tool loop itself (`generateText` with `maxSteps`), so
/// a reply arrives whole rather than streamed; its `streamText` doesn't
/// execute tools.
package struct TachikomaBackend: ChatResponding, @unchecked Sendable {
    package let model: LanguageModel
    /// Carries the credentials. Built explicitly — never read from the
    /// environment or `~/.tachikoma` behind our back.
    package let configuration: TachikomaConfiguration
    package var tools: [AssistantTool] = []
    /// Built for each reply, with the date at that moment.
    package var instructions: @Sendable (Date) -> String = { AssistantInstructions.full(now: $0) }
    package var now: @Sendable () -> Date = { Date() }
    package var maxSteps = 5

    /// The backend for a provider the user opted into. Adding a provider
    /// adds a case here.
    package static func provider(_ kind: AssistantProviderKind, configuration: ProviderConfiguration,
                                 tools: [AssistantTool], instructions: @escaping @Sendable (Date) -> String) -> TachikomaBackend {
        switch kind {
        case .openRouter:
            return .openRouter(modelID: configuration.modelID.trimmingCharacters(in: .whitespacesAndNewlines),
                               apiKey: configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                               tools: tools, instructions: instructions)
        }
    }

    package static func openRouter(modelID: String, apiKey: String, tools: [AssistantTool],
                                   instructions: @escaping @Sendable (Date) -> String = { AssistantInstructions.full(now: $0) }) -> TachikomaBackend {
        TachikomaBackend(
            model: .openRouter(modelId: modelID),
            configuration: TachikomaConfiguration(apiKeys: ["openrouter": apiKey]),
            tools: tools,
            instructions: instructions
        )
    }

    package func reply(to conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        let messages = [ModelMessage.system(instructions(now()))] + conversation.compactMap(Self.modelMessage)
        let agentTools = tools.map(Self.agentTool)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await generateText(
                        model: model,
                        messages: messages,
                        tools: agentTools.isEmpty ? nil : agentTools,
                        maxSteps: maxSteps,
                        configuration: configuration
                    )
                    continuation.yield(result.text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Earlier turns as the model sees them; an unanswered ("thinking")
    /// assistant turn isn't part of the history.
    package static func modelMessage(_ message: ChatMessage) -> ModelMessage? {
        switch message.role {
        case .user: return .user(message.text)
        case .assistant: return message.isPending || message.text.isEmpty ? nil : .assistant(message.text)
        }
    }

    // MARK: - Tools

    package static func agentTool(_ tool: AssistantTool) -> AgentTool {
        let properties = Dictionary(uniqueKeysWithValues: tool.parameters.map { parameter in
            (parameter.name, AgentToolParameterProperty(
                name: parameter.name,
                type: parameterType(parameter.kind),
                description: parameter.description,
                enumValues: parameter.enumValues
            ))
        })
        let required = tool.parameters.filter(\.isRequired).map(\.name)
        return AgentTool(
            name: tool.name,
            description: tool.description,
            parameters: AgentToolParameters(properties: properties, required: required)
        ) { arguments in
            let values = try arguments.keys.reduce(into: [String: JSONValue]()) { result, key in
                if let value = arguments[key] { result[key] = try jsonValue(value) }
            }
            return AnyAgentToolValue(string: try await tool.call(AssistantToolArguments(values)))
        }
    }

    private static func parameterType(_ kind: AssistantToolParameterKind) -> AgentToolParameterProperty.ParameterType {
        switch kind {
        case .string: return .string
        case .number: return .number
        case .integer: return .integer
        case .boolean: return .boolean
        }
    }

    private static func jsonValue(_ value: AnyAgentToolValue) throws -> JSONValue {
        let data = try JSONSerialization.data(withJSONObject: try value.toJSON(), options: .fragmentsAllowed)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
#endif
