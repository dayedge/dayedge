import Foundation

/// Which model answers Ask. Local only unless the user opts into
/// a provider with their own key; each provider's key and model are kept
/// while switching between them.
package struct AssistantSettings: Codable, Equatable, Sendable {
    /// nil = Apple's on-device model only (the default).
    package var activeProvider: AssistantProviderKind?
    package var providers: [AssistantProviderKind: ProviderConfiguration] = [:]
    /// Changes the app may make without asking (chosen with "Always
    /// Allow …" on a remote model's card). Never deletions.
    package var alwaysAllowed: Set<ChangeKind> = []

    package static let localOnly = AssistantSettings()

    package init(activeProvider: AssistantProviderKind? = nil,
                 providers: [AssistantProviderKind: ProviderConfiguration] = [:],
                 alwaysAllowed: Set<ChangeKind> = []) {
        self.activeProvider = activeProvider
        self.providers = providers
        self.alwaysAllowed = alwaysAllowed.filter { !$0.isDestructive }
    }

    private enum CodingKeys: String, CodingKey {
        case activeProvider, providers, alwaysAllowed
    }

    /// Files written before a field existed still load, keeping the rest.
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeProvider = try container.decodeIfPresent(AssistantProviderKind.self, forKey: .activeProvider)
        providers = try container.decodeIfPresent([AssistantProviderKind: ProviderConfiguration].self, forKey: .providers) ?? [:]
        let allowed = (try? container.decodeIfPresent([String].self, forKey: .alwaysAllowed)) ?? []
        alwaysAllowed = Set(allowed.compactMap(ChangeKind.init(rawValue:)).filter { !$0.isDestructive })
    }

    package var isUsingProvider: Bool { activeProvider != nil }

    /// What's stored for `kind`, or a fresh configuration with its
    /// suggested model.
    package func configuration(for kind: AssistantProviderKind) -> ProviderConfiguration {
        providers[kind] ?? ProviderConfiguration(modelID: kind.suggestedModelID)
    }

    /// The provider to use: chosen, with a key and a model. nil otherwise.
    package var readyProvider: (kind: AssistantProviderKind, configuration: ProviderConfiguration)? {
        guard let kind = activeProvider else { return nil }
        let configuration = configuration(for: kind)
        return configuration.isComplete ? (kind, configuration) : nil
    }
}

package struct ProviderConfiguration: Codable, Equatable, Sendable {
    package var apiKey = ""
    package var modelID: String

    package var isComplete: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
