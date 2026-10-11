import AppKit
import XCTest
@testable import Shell
@testable import Domain

final class MenuBarCompositionTests: XCTestCase {
    private var contextual: MenuBarMeetingPresentation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return .contextual(state: .free(until: Date(timeIntervalSince1970: 0)), configuration: .default,
                           calendar: calendar, timeFormat: .twentyFourHour)
    }

    private func plan(_ mode: MenuBarItemPresentation, meeting: MenuBarMeetingPresentation?) -> MenuBarCompositionPlan {
        MenuBarCompositionStrategy(presentation: mode).plan(
            configuration: MenuBarDateTimeConfiguration(presentation: mode),
            badge: MenuBarBadgeContent(number: 11, isOverflow: false), cornerGlyph: .tasksDue,
            text: mode.showsDateTime ? "11 Oct  06:57" : "", meeting: meeting
        )
    }

    func testIconModeEmbedsCall() {
        let result = plan(.icon, meeting: .callIcon(.zoom))
        XCTAssertEqual(result.primary.meeting, .callIcon(.zoom))
        XCTAssertNil(result.meeting)
    }

    func testIconModeEmbedsContextualMeeting() {
        let result = plan(.icon, meeting: contextual)
        XCTAssertEqual(result.primary.meeting, contextual)
        XCTAssertNil(result.meeting)
    }

    func testDateTimeModeSeparatesCall() {
        let result = plan(.dateTime, meeting: .callIcon(.zoom))
        XCTAssertNil(result.primary.meeting)
        XCTAssertFalse(result.primary.showsIcon)
        XCTAssertEqual(result.meeting, .callIcon(.zoom))
    }

    func testDateTimeModeSeparatesContextualMeeting() {
        let result = plan(.dateTime, meeting: contextual)
        XCTAssertNil(result.primary.meeting)
        XCTAssertEqual(result.meeting, contextual)
    }

    func testIconAndDateTimeModeSeparatesCall() {
        let result = plan(.iconAndDateTime, meeting: .callIcon(.zoom))
        XCTAssertNil(result.primary.meeting)
        XCTAssertTrue(result.primary.showsIcon)
        XCTAssertEqual(result.meeting, .callIcon(.zoom))
    }

    func testIconAndDateTimeModeSeparatesContextualMeeting() {
        let result = plan(.iconAndDateTime, meeting: contextual)
        XCTAssertNil(result.primary.meeting)
        XCTAssertEqual(result.meeting, contextual)
    }

    func testAbsentMeetingLeavesIconModeWithoutAccessory() {
        let result = plan(.icon, meeting: nil)
        XCTAssertNil(result.primary.meeting)
        XCTAssertNil(result.meeting)
    }

    func testAbsentMeetingLeavesDateTimeModeWithoutAccessory() {
        let result = plan(.dateTime, meeting: nil)
        XCTAssertNil(result.primary.meeting)
        XCTAssertNil(result.meeting)
    }

    func testAbsentMeetingLeavesCombinedDateTimeModeWithoutAccessory() {
        let result = plan(.iconAndDateTime, meeting: nil)
        XCTAssertNil(result.primary.meeting)
        XCTAssertNil(result.meeting)
    }

    func testCallRegionStartsAfterCalendarCanvas() {
        let geometry = MenuBarPrimaryGeometry(imageRect: CGRect(x: 6, y: 0, width: 40, height: 22),
                                              titleRect: .zero, badgeWidth: 24.5, hasCallIcon: true)
        XCTAssertFalse(geometry.isMeetingHit(CGPoint(x: 29, y: 11)))
        XCTAssertTrue(geometry.isMeetingHit(CGPoint(x: 32, y: 11)))
    }

    func testContextualRegionUsesNativeTitleRect() {
        let geometry = MenuBarPrimaryGeometry(imageRect: CGRect(x: 6, y: 0, width: 20, height: 22),
                                              titleRect: CGRect(x: 30, y: 0, width: 100, height: 22),
                                              badgeWidth: 20, hasCallIcon: false)
        XCTAssertFalse(geometry.isMeetingHit(CGPoint(x: 16, y: 11)))
        XCTAssertTrue(geometry.isMeetingHit(CGPoint(x: 60, y: 11)))
    }

    func testCalendarAnchorIgnoresCombinedImageWidth() {
        let geometry = MenuBarPrimaryGeometry(imageRect: CGRect(x: 6, y: 0, width: 40, height: 22),
                                              titleRect: .zero, badgeWidth: 20, hasCallIcon: true)
        XCTAssertEqual(geometry.calendarCenterX, 16)
    }
}

@MainActor
final class MenuBarPrimaryRendererTests: XCTestCase {
    private func primary(meeting: MenuBarMeetingPresentation?, glyph: MenuBarCornerGlyph? = nil,
                         text: String = "") -> MenuBarPrimaryPresentation {
        MenuBarPrimaryPresentation(badge: MenuBarBadgeContent(number: 11, isOverflow: false),
                                   cornerGlyph: glyph, text: text, showsIcon: true, meeting: meeting)
    }

    func testCombinedCallImageIsReused() throws {
        let renderer = MenuBarPrimaryRenderer()
        let first = renderer.render(primary(meeting: .callIcon(.zoom)), scale: 2)
        let next = renderer.render(primary(meeting: .callIcon(.zoom)), scale: 2)
        XCTAssertNotNil(first.image)
        XCTAssertTrue(first.image === next.image)
        XCTAssertGreaterThan(try XCTUnwrap(first.image).size.width, first.badgeWidth)
    }

    func testChangedServiceReplacesCombinedImage() {
        let renderer = MenuBarPrimaryRenderer()
        let first = renderer.render(primary(meeting: .callIcon(.zoom)), scale: 2)
        let next = renderer.render(primary(meeting: .callIcon(.teams)), scale: 2)
        XCTAssertFalse(first.image === next.image)
    }

    func testChangedGlyphReplacesCombinedImage() {
        let renderer = MenuBarPrimaryRenderer()
        let first = renderer.render(primary(meeting: .callIcon(.zoom)), scale: 2)
        let next = renderer.render(primary(meeting: .callIcon(.zoom), glyph: .tasksDue), scale: 2)
        XCTAssertFalse(first.image === next.image)
    }

    func testChangedScaleReplacesCombinedImage() {
        let renderer = MenuBarPrimaryRenderer()
        let first = renderer.render(primary(meeting: .callIcon(.zoom)), scale: 1)
        let next = renderer.render(primary(meeting: .callIcon(.zoom)), scale: 2)
        XCTAssertFalse(first.image === next.image)
    }

    func testDateTimeTextChangeReusesBadge() {
        let renderer = MenuBarPrimaryRenderer()
        let first = renderer.render(primary(meeting: nil, text: "06:57"), scale: 2)
        let next = renderer.render(primary(meeting: nil, text: "06:58"), scale: 2)
        XCTAssertTrue(first.image === next.image)
        XCTAssertEqual(next.text, "06:58")
    }

    func testCountdownChangeReusesBadge() {
        let renderer = MenuBarPrimaryRenderer()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let event = AgendaEventModel(id: "meeting", startTime: "10:00", title: "Meeting")
        func meeting(_ remaining: Int) -> MenuBarMeetingPresentation {
            .contextual(state: .ongoing(event: event, minutesRemaining: remaining), configuration: .default,
                        calendar: calendar, timeFormat: .twentyFourHour)
        }
        let first = renderer.render(primary(meeting: meeting(5)), scale: 2)
        let next = renderer.render(primary(meeting: meeting(4)), scale: 2)
        XCTAssertTrue(first.image === next.image)
        XCTAssertNotEqual(first.text, next.text)
    }

    func testEndingCallRestoresCalendarOnlyImage() throws {
        let renderer = MenuBarPrimaryRenderer()
        let call = renderer.render(primary(meeting: .callIcon(.zoom)), scale: 2)
        let ended = renderer.render(primary(meeting: nil), scale: 2)
        XCTAssertFalse(ended.hasCallIcon)
        XCTAssertEqual(try XCTUnwrap(ended.image).size.width, ended.badgeWidth)
        XCTAssertLessThan(ended.badgeWidth, try XCTUnwrap(call.image).size.width)
    }
}
