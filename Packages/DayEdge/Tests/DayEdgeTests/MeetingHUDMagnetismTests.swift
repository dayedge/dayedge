import XCTest
@testable import Shell

final class MeetingHUDMagnetismTests: XCTestCase {
    private let magnetism = MeetingHUDMagnetism()

    func testOutsideInfluenceRadiusIsUnchanged() {
        XCTAssertEqual(magnetism.adjustedCenterX(rawCenterX: 1_080, targetCenterX: 1_000), 1_080)
        XCTAssertEqual(magnetism.adjustedCenterX(rawCenterX: 920, targetCenterX: 1_000), 920)
    }

    func testAttractionStrengthProgressivelyIncreasesTowardCenter() {
        XCTAssertEqual(
            magnetism.adjustedCenterX(rawCenterX: 1_060, targetCenterX: 1_000),
            1_050.625,
            accuracy: 0.001
        )
        XCTAssertEqual(
            magnetism.adjustedCenterX(rawCenterX: 1_035, targetCenterX: 1_000),
            1_014.235,
            accuracy: 0.001
        )
        XCTAssertEqual(
            magnetism.adjustedCenterX(rawCenterX: 1_015, targetCenterX: 1_000),
            1_001.384,
            accuracy: 0.001
        )
    }

    func testAttractionIsSymmetric() {
        let right = magnetism.adjustedCenterX(rawCenterX: 1_035, targetCenterX: 1_000) - 1_000
        let left = 1_000 - magnetism.adjustedCenterX(rawCenterX: 965, targetCenterX: 1_000)
        XCTAssertEqual(left, right, accuracy: 0.000_1)
    }

    func testVeryClosePositionSnapsExactlyToCenter() {
        XCTAssertEqual(magnetism.adjustedCenterX(rawCenterX: 1_006, targetCenterX: 1_000), 1_000)
        XCTAssertEqual(magnetism.adjustedCenterX(rawCenterX: 994, targetCenterX: 1_000), 1_000)
    }

    func testReleaseSettleUsesDedicatedLargerRadius() {
        XCTAssertTrue(magnetism.shouldSettleOnCenter(rawCenterX: 1_036, targetCenterX: 1_000))
        XCTAssertFalse(magnetism.shouldSettleOnCenter(rawCenterX: 1_037, targetCenterX: 1_000))
    }

    func testAdjustedDistanceIsMonotonic() {
        var previousDistance: CGFloat = 0
        for rawDistance in stride(from: CGFloat(0), through: 80, by: 1) {
            let adjusted = magnetism.adjustedCenterX(rawCenterX: 1_000 + rawDistance, targetCenterX: 1_000)
            let adjustedDistance = adjusted - 1_000
            XCTAssertGreaterThanOrEqual(adjustedDistance + 0.000_1, previousDistance)
            previousDistance = adjustedDistance
        }
    }
}
