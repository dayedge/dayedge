import XCTest
@testable import Shell
@testable import Domain
@testable import Platform

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.handler?(request) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor CountingProvider: HolidayProviding {
    private(set) var calls = 0
    var fail = false
    func setFail(_ v: Bool) { fail = v }
    func holidays(region: String, year: Int) async throws -> [PublicHoliday] {
        calls += 1
        if fail { throw URLError(.notConnectedToInternet) }
        return [PublicHoliday(dateKey: "\(year)-01-01", name: "New Year")]
    }
    func supportedRegions() async throws -> Set<String> { ["PL"] }
}

final class HolidayProviderTests: XCTestCase {
    private let json = """
    [
     {"id":"1","startDate":"2026-01-01","endDate":"2026-01-01","type":"Public","nationwide":true,
      "name":[{"language":"EN","text":"New Year's Day"},{"language":"PL","text":"Nowy Rok"}]},
     {"id":"2","startDate":"2026-04-05","endDate":"2026-04-06","type":"Public","nationwide":true,
      "name":[{"language":"EN","text":"Easter"}]},
     {"id":"3","startDate":"2026-05-01","endDate":"2026-05-01","type":"Public","nationwide":false,
      "name":[{"language":"EN","text":"Regional"}]},
     {"id":"4","startDate":"2026-06-01","endDate":"2026-06-01","type":"School","nationwide":true,
      "name":[{"language":"EN","text":"School"}]}
    ]
    """

    private func provider(language: String) -> OpenHolidaysProvider {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { [json] _ in Data(json.utf8) }
        return OpenHolidaysProvider(session: URLSession(configuration: config), languageCode: language)
    }

    func testFiltersExpandsAndLocalizes() async throws {
        let result = try await provider(language: "pl").holidays(region: "PL", year: 2026)
        XCTAssertEqual(result.map(\.dateKey), ["2026-01-01", "2026-04-05", "2026-04-06"])
        XCTAssertEqual(result.first?.name, "Nowy Rok")
        XCTAssertEqual(result.last?.name, "Easter") // falls back to EN
    }

    func testDiskCacheServesOfflineAndStaleFallback() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let upstream = CountingProvider()
        let cache = CachingHolidayProvider(upstream: upstream, directory: dir, languageCode: "en", maxAge: 3600)

        _ = try await cache.holidays(region: "PL", year: 2026)
        _ = try await cache.holidays(region: "PL", year: 2026)
        let calls = await upstream.calls
        XCTAssertEqual(calls, 1)

        // Expired cache + failing upstream still returns the stale copy.
        let expired = CachingHolidayProvider(upstream: upstream, directory: dir, languageCode: "en",
                                             maxAge: -1)
        await upstream.setFail(true)
        let stale = try await expired.holidays(region: "PL", year: 2026)
        XCTAssertEqual(stale.count, 1)

        // No cache + failing upstream throws.
        do {
            _ = try await expired.holidays(region: "DE", year: 2026)
            XCTFail("expected throw")
        } catch {}
    }
}
