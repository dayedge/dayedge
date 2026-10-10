import XCTest
@testable import Agenda

final class DayAdvanceTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_790_000_000)
    private var nextDay: Date { day.addingTimeInterval(86_400) }

    func testALaterDayArrivesFromTheRight() {
        XCTAssertEqual(DayAdvance.startOffset(from: day, to: nextDay, reduceMotion: false), DayAdvance.distance)
    }

    func testAnEarlierDayArrivesFromTheLeft() {
        XCTAssertEqual(DayAdvance.startOffset(from: nextDay, to: day, reduceMotion: false), -DayAdvance.distance)
    }

    func testReduceMotionRemovesTheMovement() {
        XCTAssertEqual(DayAdvance.startOffset(from: day, to: nextDay, reduceMotion: true), 0)
    }
}
