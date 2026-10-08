import XCTest
@testable import Shell
@testable import UI

/// The mixed agenda's marker grid: different markers, one axis.
final class AgendaRowGeometryTests: XCTestCase {
    func testTaskRingStaysAControlDistinctFromAnEventDot() {
        let eventDot: CGFloat = 10 // `AgendaEventRowView.statusIndicator`
        XCTAssertGreaterThanOrEqual(AppTheme.Tasks.embeddedRingSize, 17, "below ~17pt a ring reads as a dot with a hole")
        XCTAssertGreaterThan(AppTheme.Tasks.embeddedRingSize, eventDot)
        XCTAssertLessThanOrEqual(AppTheme.Tasks.embeddedRingSize, AppTheme.AgendaRow.markerSlotWidth,
                                 "the ring fits the shared slot, so it never pushes the text")
        XCTAssertGreaterThan(AppTheme.AgendaRow.ringHitTarget, AppTheme.Tasks.embeddedRingSize, "a bit larger than the ring itself")
    }

    func testTwoFixedAnchorsDriveEveryRow() {
        typealias Row = AppTheme.AgendaRow
        // The slot is centered on the marker axis and ends where content starts.
        XCTAssertEqual(Row.leadingInset + Row.markerSlotWidth / 2, Row.markerCenterX)
        XCTAssertEqual(Row.leadingInset + Row.markerSlotWidth + Row.markerToContent, Row.contentLeadingX)
        XCTAssertGreaterThanOrEqual(Row.markerToContent, 0)
        XCTAssertLessThanOrEqual(Row.contentLeadingX, 35, "compact: content close to its markers")
    }

    func testMarkersKeepAReadableGapAndStayInsideTheRowHighlight() {
        typealias Row = AppTheme.AgendaRow
        let ringRightEdge = Row.markerCenterX + AppTheme.Tasks.embeddedRingSize / 2
        XCTAssertGreaterThanOrEqual(Row.contentLeadingX - ringRightEdge, 7, "ring must not crowd the text")
        let highlightInset: CGFloat = 8 // rows inset their rounded highlight by 8pt
        XCTAssertGreaterThanOrEqual(Row.markerCenterX - Row.ringHitTarget / 2, highlightInset)
        XCTAssertGreaterThanOrEqual(Row.markerCenterX - AppTheme.Tasks.embeddedRingSize / 2, highlightInset + 2,
                                    "the ring sits visibly inside a selected row's surface")
    }
}
