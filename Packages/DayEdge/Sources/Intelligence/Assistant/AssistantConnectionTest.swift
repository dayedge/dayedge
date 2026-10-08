import Foundation

/// Checks a provider's key and model with one tiny request, through the
/// same backend Ask uses — for providers with no model list to
/// verify against. Only runs when the user asks (Settings → Test).
package enum AssistantConnectionTest {
    package enum Outcome: Equatable {
        case works
        case failed(String)
    }

    package static func run(_ kind: AssistantProviderKind, configuration: ProviderConfiguration) async -> Outcome {
        guard configuration.isComplete else { return .failed("Enter a key and a model id first.") }
        #if canImport(Tachikoma)
        let backend = TachikomaBackend.provider(kind, configuration: configuration, tools: [], instructions: { _ in "Reply with the word OK." })
        do {
            for try await answer in backend.reply(to: [ChatMessage(role: .user, text: "Say OK.")]) where !answer.isEmpty {
                return .works
            }
            return .failed("\(kind.displayName) sent an empty answer.")
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .failed("This build of DayEdge can't use \(kind.displayName).")
        #endif
    }
}
