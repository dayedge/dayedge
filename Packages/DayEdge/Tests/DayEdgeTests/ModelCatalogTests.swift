import XCTest
@testable import Shell
@testable import Intelligence

/// Model lists: OpenRouter's live catalogue (faked network), the per-provider
/// fallbacks, and the picker's filter. No real network, no real keys.
final class ModelCatalogTests: XCTestCase {
    private let page = """
    {"data": [
      {"id": "openai/gpt-5.6-luna", "name": "OpenAI: GPT-5.6 Luna", "context_length": 400000,
       "pricing": {"prompt": "0.0000012", "completion": "0.0000096"}},
      {"id": "bare/model"},
      {"name": "no id — dropped"},
      {"id": "anthropic/claude-haiku-4.5", "name": "Anthropic: Claude Haiku 4.5", "pricing": {"prompt": 0.000001, "completion": 0.000005}}
    ]}
    """

    // MARK: - OpenRouter

    func testAsksForToolCapableModelsWithTheKeyAndReadsWhateverIsThere() async throws {
        let http = FakeHTTP(status: 200, body: page)
        let models = try await OpenRouterCatalog(http: http).models(apiKey: "sk-or-test")

        let request = try XCTUnwrap(http.lastRequest)
        XCTAssertEqual(request.url?.query, "supported_parameters=tools")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")

        XCTAssertEqual(models.map(\.id), ["anthropic/claude-haiku-4.5", "bare/model", "openai/gpt-5.6-luna"], "sorted by title; no-id entries dropped")
        let luna = try XCTUnwrap(models.first { $0.id == "openai/gpt-5.6-luna" })
        XCTAssertEqual(luna.contextLength, 400_000)
        XCTAssertEqual(luna.pricing?.inputPerMillion ?? 0, 1.2, accuracy: 0.0001)
        XCTAssertEqual(luna.pricing?.outputPerMillion ?? 0, 9.6, accuracy: 0.0001)
        let bare = try XCTUnwrap(models.first { $0.id == "bare/model" })
        XCTAssertNil(bare.name)
        XCTAssertNil(bare.pricing)
        XCTAssertEqual(bare.title, "bare/model", "no name: the id is the title")
        XCTAssertEqual(models.first?.pricing?.outputPerMillion ?? 0, 5, accuracy: 0.0001, "numeric prices are read too")
    }

    func testARejectedKeyIsReportedAsSuch() async {
        do {
            _ = try await OpenRouterCatalog(http: FakeHTTP(status: 401, body: "{}")).models(apiKey: "bad")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ModelCatalogError, .invalidKey)
        }
    }

    // MARK: - Sources: live, suggested, or type an id

    func testTheLiveListWinsWhenItLoads() async {
        let source = ModelSource(curated: [ModelOption(id: "curated/one")], live: OpenRouterCatalog(http: FakeHTTP(status: 200, body: page)))
        let listing = await source.listing(apiKey: "sk-or-test")
        XCTAssertEqual(listing.origin, .live)
        XCTAssertEqual(listing.options.count, 3)
        XCTAssertNil(listing.liveError)
    }

    func testAFailedFetchFallsBackToTheSuggestedModels() async {
        let source = ModelSource(curated: [ModelOption(id: "curated/one")], live: OpenRouterCatalog(http: FakeHTTP(status: 401, body: "{}")))
        let listing = await source.listing(apiKey: "bad")
        XCTAssertEqual(listing, ModelListing(origin: .suggested, options: [ModelOption(id: "curated/one")], liveError: .invalidKey))
        let noKey = await source.listing(apiKey: "  ")
        XCTAssertEqual(noKey.origin, .suggested, "no key: no fetch")
        XCTAssertNil(noKey.liveError)
    }

    func testAProviderWithNoListMeansTypingAnID() async {
        let listing = await ModelSource().listing(apiKey: "anything")
        XCTAssertEqual(listing, ModelListing(origin: .none, options: []))
    }

    // MARK: - What a row shows

    func testRowDetailShowsOnlyWhatIsKnown() {
        XCTAssertNil(ModelOption(id: "bare/model").detail, "nothing known: no detail, no placeholders")
        XCTAssertEqual(ModelOption(id: "a", contextLength: 128_000).detail, "128K context")
        XCTAssertEqual(ModelOption(id: "a", contextLength: 1_048_576).detail, "1.0M context")
        XCTAssertEqual(ModelOption(id: "a", pricing: .init(inputPerMillion: 1.2, outputPerMillion: 9.6)).detail, "$1.20 / $9.60 per 1M")
        XCTAssertEqual(ModelOption(id: "a", contextLength: 400_000, pricing: .init(inputPerMillion: 0.25, outputPerMillion: 2)).detail,
                       "400K context · $0.250 / $2.00 per 1M")
        XCTAssertEqual(ModelOption(id: "a", pricing: .init(inputPerMillion: 0, outputPerMillion: 0)).detail, "Free")
    }

    // MARK: - Filter

    func testFilterMatchesEveryWordInIdOrNameExactAndPrefixFirst() {
        let options = [
            ModelOption(id: "openai/gpt-5.6", name: "OpenAI: GPT-5.6"),
            ModelOption(id: "openai/gpt-5.6-luna", name: "OpenAI: GPT-5.6 Luna"),
            ModelOption(id: "luna"),
            ModelOption(id: "mistral/lunaris", name: "Lunáris Large")
        ]
        XCTAssertEqual(ModelOption.filter(options, query: "LUNA").map(\.id), ["luna", "mistral/lunaris", "openai/gpt-5.6-luna"],
                       "exact id, then a prefix (accents ignored), then the rest")
        XCTAssertEqual(ModelOption.filter(options, query: "gpt luna").map(\.id), ["openai/gpt-5.6-luna"], "every word must match")
        XCTAssertEqual(ModelOption.filter(options, query: "  ").count, 4)
    }
}

private final class FakeHTTP: HTTPClient, @unchecked Sendable {
    let status: Int
    let body: String
    private(set) var lastRequest: URLRequest?

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
