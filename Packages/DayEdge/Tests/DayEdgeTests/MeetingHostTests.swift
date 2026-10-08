import XCTest
@testable import Domain
@testable import UI

final class MeetingHostTests: XCTestCase {
    private func service(_ text: String) -> VideoConferenceService? {
        URL(string: text).flatMap(MeetingHost.service(for:))
    }

    func testOnlyTheServicesOwnHostsCount() {
        XCTAssertEqual(service("https://zoom.us/j/123"), .zoom)
        XCTAssertEqual(service("https://us02web.zoom.us/j/123"), .zoom)
        XCTAssertEqual(service("https://teams.microsoft.com/l/meetup-join/x"), .teams)
        XCTAssertEqual(service("https://teams.live.com/meet/1"), .teams)
        XCTAssertEqual(service("https://meet.google.com/abc-defg-hij"), .googleMeet)
        XCTAssertEqual(service("https://ZOOM.US./j/1"), .zoom, "case and a trailing dot")

        XCTAssertNil(service("https://teams.microsoft.com.attacker.example/x"))
        XCTAssertNil(service("https://evilzoom.us/j/1"))
        XCTAssertNil(service("https://meet.google.com.evil.io/x"))
        XCTAssertNil(service("https://example.com/?u=zoom.us"))
    }

    func testOnlyWebLinksAreJoinable() {
        XCTAssertNil(service("zoommtg://zoom.us/join?confno=1"))
        XCTAssertNil(service("file:///Applications/Calculator.app"))
        XCTAssertNil(MeetingLink.resolve(service: .other, videoURLString: "javascript:alert(1)")?.webURL)
        XCTAssertNil(MeetingLink.resolve(service: .other, videoURLString: "file:///etc/passwd")?.webURL)
        XCTAssertNil(MeetingLink.resolve(service: .other, videoURLString: "someapp://do-something")?.webURL)
        XCTAssertNotNil(MeetingLink.resolve(service: .other, videoURLString: "https://example.com/call")?.webURL)
    }

    func testAppLinksOnlyForTheRealService() throws {
        let fake = try XCTUnwrap(URL(string: "https://teams.microsoft.com.attacker.example/l/x"))
        XCTAssertNil(MeetingAppLinkConverter.appURL(for: .teams, webURL: fake))
        let real = try XCTUnwrap(URL(string: "https://teams.microsoft.com/l/x"))
        XCTAssertEqual(MeetingAppLinkConverter.appURL(for: .teams, webURL: real)?.scheme, "msteams")
    }
}
