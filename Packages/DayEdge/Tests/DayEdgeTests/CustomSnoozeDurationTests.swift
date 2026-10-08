import XCTest
@testable import Shell

final class CustomSnoozeDurationTests: XCTestCase {
    func testBareNumbersAreMinutes() {
        XCTAssertEqual(CustomSnoozeDuration.parse("5"), 5)
        XCTAssertEqual(CustomSnoozeDuration.parse("90"), 90)
        XCTAssertEqual(CustomSnoozeDuration.parse("120"), 120)
    }

    func testInvalidInputIsRejectedQuietly() {
        for input in ["", "0", "-2", "121", "meeting", "1h", "3 minutes"] {
            XCTAssertNil(CustomSnoozeDuration.parse(input), input)
        }
    }

    func testDisplayAlwaysUsesMinutes() {
        XCTAssertEqual(CustomSnoozeDuration.display(1), "1 minute")
        XCTAssertEqual(CustomSnoozeDuration.display(5), "5 minutes")
        XCTAssertEqual(CustomSnoozeDuration.display(60), "60 minutes")
        XCTAssertEqual(CustomSnoozeDuration.display(90), "90 minutes")
        XCTAssertEqual(CustomSnoozeDuration.display(120), "120 minutes")
    }
}
