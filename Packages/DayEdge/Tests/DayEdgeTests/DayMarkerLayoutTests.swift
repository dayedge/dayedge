import SwiftUI
import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

final class DayMarkerLayoutTests: XCTestCase {
    private let dot = DotStyle(tint: .blue)

    private func layout(events: Int, task: Bool) -> [DayMarker] {
        DayMarkerLayout.markers(
            dots: Array(repeating: dot, count: events),
            taskColor: task ? .red : nil,
            slots: 4
        )
    }

    func testEventsOnlyFillAllFourSlots() {
        XCTAssertEqual(layout(events: 4, task: false), Array(repeating: .event(dot), count: 4))
    }

    func testEventOverflowWithoutTaskShowsThreeDotsAndPlus() {
        XCTAssertEqual(layout(events: 6, task: false), [.event(dot), .event(dot), .event(dot), .moreEvents])
    }

    func testTaskAloneShowsTick() {
        XCTAssertEqual(layout(events: 0, task: true), [.task(.red)])
    }

    func testThreeEventsAndTaskStillFit() {
        XCTAssertEqual(layout(events: 3, task: true), [.event(dot), .event(dot), .event(dot), .task(.red)])
    }

    func testTaskTakesASlotSoFourEventsOverflow() {
        XCTAssertEqual(layout(events: 4, task: true), [.event(dot), .event(dot), .moreEvents, .task(.red)])
    }

    func testRowNeverExceedsSlots() {
        XCTAssertEqual(layout(events: 9, task: true).count, 4)
    }
}
