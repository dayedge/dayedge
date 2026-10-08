import Foundation

/// One model a provider offers. Only `id` is certain; everything else is
/// filled in when the provider says it, never invented — the picker shows
/// just what's there.
package struct ModelOption: Identifiable, Equatable, Sendable {
    package struct Pricing: Equatable, Sendable {
        /// US dollars per million tokens.
        package var inputPerMillion: Double
        package var outputPerMillion: Double
    }

    package let id: String
    package var name: String?
    package var contextLength: Int?
    package var pricing: Pricing?

    /// What the picker shows as the row's title.
    package var title: String { name?.isEmpty == false ? name! : id }

    /// "400K context · $1.20 / $9.60 per 1M" — only the parts that are
    /// known; nil when none are.
    package var detail: String? {
        var parts: [String] = []
        if let contextLength, contextLength > 0 {
            parts.append(contextLength >= 1_000_000
                ? "\(Self.trimmed(Double(contextLength) / 1_000_000))M context"
                : "\(contextLength / 1_000)K context")
        }
        if let pricing {
            parts.append(pricing.inputPerMillion == 0 && pricing.outputPerMillion == 0
                ? "Free"
                : "$\(Self.price(pricing.inputPerMillion)) / $\(Self.price(pricing.outputPerMillion)) per 1M")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func price(_ value: Double) -> String {
        String(format: value < 1 ? "%.3f" : "%.2f", value)
    }

    /// Options matching `query`: every word must appear in the id or the
    /// name (case and accents ignored). Exact matches first, then prefixes,
    /// then the rest, each in the list's own order.
    package static func filter(_ options: [ModelOption], query: String) -> [ModelOption] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return options }
        let matching = options.filter { option in
            let haystack = fold(option.id + " " + (option.name ?? ""))
            return words.allSatisfy(haystack.contains)
        }
        let phrase = words.joined(separator: " ")
        func rank(_ option: ModelOption) -> Int {
            let id = fold(option.id), name = fold(option.name ?? "")
            let shortID = id.split(separator: "/").last.map(String.init) ?? id
            if id == phrase || name == phrase || shortID == phrase { return 0 }
            if id.hasPrefix(phrase) || name.hasPrefix(phrase) || shortID.hasPrefix(phrase) { return 1 }
            return 2
        }
        return matching.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// A provider's live list of models, fetched with the user's key.
package protocol ModelCatalog: Sendable {
    func models(apiKey: String) async throws -> [ModelOption]
}

package enum ModelCatalogError: Error, Equatable {
    case invalidKey
    case offline
    case unexpected(String)
}

/// The network, as the catalogues need it — faked in tests.
package protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

package struct URLSessionHTTPClient: HTTPClient {
    package func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}
