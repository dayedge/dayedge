import Foundation

/// A remote model provider the user can opt into with their own key.
/// Adding one = a case here, its model source (`AssistantProviderKind.modelSource`)
/// and its backend mapping (`AssistantBackendResolver`).
package enum AssistantProviderKind: String, Codable, CaseIterable, Identifiable, Sendable, CodingKeyRepresentable {
    case openRouter

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        }
    }

    /// Where the user gets a key.
    package var keysURL: URL {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/settings/keys")!
        }
    }

    package var keyPlaceholder: String {
        switch self {
        case .openRouter: return "sk-or-…"
        }
    }

    /// The model preselected until the user picks one.
    package var suggestedModelID: String {
        switch self {
        case .openRouter: return "openai/gpt-5.6-luna"
        }
    }
}
