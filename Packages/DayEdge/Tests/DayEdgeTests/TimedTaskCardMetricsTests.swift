import XCTest
@testable import Shell
@testable import UI

final class TimedTaskCardMetricsTests: XCTestCase {
    func testTheHeightIsTheContentsNeverADuration() {
        let standard = TimedTaskCardMetrics.height(hasSecondLine: true)
        XCTAssertEqual(standard, 49)
        XCTAssertTrue((44...52).contains(standard), "a title + list card stays compact")
        XCTAssertEqual(TimedTaskCardMetrics.height(hasSecondLine: false), 32, "title only: shorter still")
    }

    func testTheRingIsCenteredOnTheTitlesFirstLine() {
        XCTAssertEqual(AppTheme.Tasks.timelineCardRingCenter,
                       TimedTaskCardMetrics.verticalPadding + AppTheme.AgendaRow.firstLineCenter,
                       "so the ring — not the card's middle — sits on the due minute")
    }
}

extension TimedTaskCardMetricsTests {
    func testTheCardsRingHasAGenerousClickArea() {
        XCTAssertGreaterThanOrEqual(AppTheme.Tasks.timelineCardRingHitTarget, 24)
        XCTAssertLessThanOrEqual(AppTheme.Tasks.timelineCardRingHitTarget / 2,
                                 AppTheme.Tasks.timelineCardPaddingH + AppTheme.Tasks.embeddedRingSize / 2,
                                 "it stays within the card")
    }
}
