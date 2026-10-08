import Foundation

/// Where a provider's models come from — providers differ a lot, so this is
/// described per provider rather than assumed: a live catalogue fetched with
/// the key, a curated list shipped with the app, both, or neither. Typing a
/// model id by hand is always possible on top.
package struct ModelSource: Sendable {
    package var curated: [ModelOption] = []
    package var live: (any ModelCatalog)?

    package var hasLiveCatalog: Bool { live != nil }

    /// The list to offer: live when it loads, else curated, else none —
    /// a failed fetch never blocks, it falls back.
    package func listing(apiKey: String) async -> ModelListing {
        var liveError: ModelCatalogError?
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let live, !key.isEmpty {
            do {
                return ModelListing(origin: .live, options: try await live.models(apiKey: key))
            } catch let error as ModelCatalogError {
                liveError = error
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .timedOut
                        || error.code == .cannotFindHost || error.code == .networkConnectionLost {
                liveError = .offline
            } catch {
                liveError = .unexpected(error.localizedDescription)
            }
        }
        return curated.isEmpty
            ? ModelListing(origin: .none, options: [], liveError: liveError)
            : ModelListing(origin: .suggested, options: curated, liveError: liveError)
    }
}

package struct ModelListing: Equatable {
    package enum Origin: Equatable {
        /// The provider's current list.
        case live
        /// The app's own short list for this provider.
        case suggested
        /// Nothing to pick from: the model id is typed.
        case none
    }

    package var origin: Origin
    package var options: [ModelOption]
    /// Why the live list isn't the one shown, when a fetch was tried.
    package var liveError: ModelCatalogError?
}

extension AssistantProviderKind {
    package func modelSource(http: any HTTPClient = URLSessionHTTPClient()) -> ModelSource {
        switch self {
        case .openRouter:
            // Ids only: names and prices come from the live list, never guessed.
            return ModelSource(
                curated: [ModelOption(id: "openai/gpt-5.6-luna"), ModelOption(id: "anthropic/claude-haiku-4.5")],
                live: OpenRouterCatalog(http: http)
            )
        }
    }
}
