import XCTest
@testable import Shell
@testable import Domain

final class LocationMapsHeuristicTests: XCTestCase {
    func testGenericVirtualLocationsAreNotMappable() {
        XCTAssertFalse(LocationMapsHeuristic.isLikelyMappableLocation("Office"))
        XCTAssertFalse(LocationMapsHeuristic.isLikelyMappableLocation("Meeting Room"))
        XCTAssertFalse(LocationMapsHeuristic.isLikelyMappableLocation("Teams Meeting"))
    }

    func testStreetAddressIsMappable() {
        XCTAssertTrue(LocationMapsHeuristic.isLikelyMappableLocation("123 Main St, Springfield"))
    }

    func testPlainVenueNameIsMappable() {
        XCTAssertTrue(LocationMapsHeuristic.isLikelyMappableLocation("Blue Bottle Coffee"))
    }

    func testBareMeetingURLIsNotMappable() {
        XCTAssertFalse(LocationMapsHeuristic.isLikelyMappableLocation("https://zoom.us/j/123456789"))
    }

    func testEmptyOrWhitespaceIsNotMappable() {
        XCTAssertFalse(LocationMapsHeuristic.isLikelyMappableLocation(""))
        XCTAssertFalse(LocationMapsHeuristic.isLikelyMappableLocation("   "))
    }
}
