import Foundation

/// OpenRouter's live model list, limited to models that can call tools
/// (the assistant needs them). Read defensively: only `id` is required;
/// name, context length and prices are used when present.
package struct OpenRouterCatalog: ModelCatalog {
    package static let endpoint = URL(string: "https://openrouter.ai/api/v1/models?supported_parameters=tools")!

    package let http: any HTTPClient

    package func models(apiKey: String) async throws -> [ModelOption] {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw ModelCatalogError.invalidKey }
        guard (200..<300).contains(status) else { throw ModelCatalogError.unexpected("HTTP \(status)") }

        guard let page = try? JSONDecoder().decode(Page.self, from: data) else {
            throw ModelCatalogError.unexpected("Unreadable model list")
        }
        return page.data.compactMap(\.option).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private struct Page: Decodable {
        let data: [OpenRouterEntry]
    }

}

/// Every field optional, so one odd entry never sinks the list.
private struct OpenRouterEntry: Decodable {
    let id: String?
    let name: String?
    let contextLength: Int?
    let prompt: Double?
    let completion: Double?

    enum CodingKeys: String, CodingKey { case id, name, contextLength = "context_length", pricing }
    enum PricingKeys: String, CodingKey { case prompt, completion }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decode(String.self, forKey: .id)
        name = try? container.decode(String.self, forKey: .name)
        contextLength = try? container.decode(Int.self, forKey: .contextLength)
        let pricing = try? container.nestedContainer(keyedBy: PricingKeys.self, forKey: .pricing)
        prompt = pricing.flatMap { Self.price($0, .prompt) }
        completion = pricing.flatMap { Self.price($0, .completion) }
    }

    /// Prices come as strings ("0.000003", per token); tolerate numbers.
    private static func price(_ container: KeyedDecodingContainer<PricingKeys>, _ key: PricingKeys) -> Double? {
        if let text = try? container.decode(String.self, forKey: key) { return Double(text) }
        return try? container.decode(Double.self, forKey: key)
    }

    var option: ModelOption? {
        guard let id, !id.isEmpty else { return nil }
        var pricing: ModelOption.Pricing?
        if let prompt, let completion, prompt >= 0, completion >= 0 {
            pricing = ModelOption.Pricing(inputPerMillion: prompt * 1_000_000, outputPerMillion: completion * 1_000_000)
        }
        return ModelOption(id: id, name: name, contextLength: contextLength, pricing: pricing)
    }
}
