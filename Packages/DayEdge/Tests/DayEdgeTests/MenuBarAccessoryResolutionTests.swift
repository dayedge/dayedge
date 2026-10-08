import XCTest
@testable import Shell
@testable import Domain

final class MenuBarAccessoryResolutionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute))!
    }

    private func event(
        _ id: String, _ start: String, _ end: String,
        videoService: VideoConferenceService? = nil, videoURL: String? = nil
    ) -> AgendaEventModel {
        AgendaEventModel(
            id: id, startTime: start, endTime: end,
            startDate: parseTime(start), endDate: parseTime(end),
            title: id, videoService: videoService, videoURL: videoURL
        )
    }

    private func parseTime(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":")
        return date(Int(parts[0])!, Int(parts[1])!)
    }

    private var enabledIndicatorConfiguration: MenuBarEventIndicatorConfiguration {
        var configuration = MenuBarEventIndicatorConfiguration.default
        configuration.isEnabled = true
        return configuration
    }

    private var disabledIndicatorConfiguration: MenuBarEventIndicatorConfiguration {
        var configuration = MenuBarEventIndicatorConfiguration.default
        configuration.isEnabled = false
        return configuration
    }

    func testEnabledIndicatorWithResolvableStateReturnsContextualAccessoryAndMatchingReadyCallEvent() {
        let meeting = event("Planning", "10:00", "11:00", videoService: .zoom, videoURL: "https://zoom.us/j/1")
        let resolution = resolveMenuBarAccessory(
            events: [meeting], on: date(0), now: date(9, 50), calendar: calendar,
            indicatorConfiguration: enabledIndicatorConfiguration,
            callReadinessStrategy: .leadTime(minutes: 15)
        )

        guard case .contextual = resolution.accessory else {
            return XCTFail("expected a contextual accessory")
        }
        XCTAssertEqual(resolution.readyCallEvent?.id, "Planning")
    }

    func testEnabledIndicatorWithNoResolvableStateReturnsNilAccessoryAndNilReadyCallEvent() {
        let meeting = event("Later", "10:00", "11:00", videoService: .zoom, videoURL: "https://zoom.us/j/1")
        let resolution = resolveMenuBarAccessory(
            events: [meeting], on: date(0), now: date(8, 0), calendar: calendar,
            indicatorConfiguration: enabledIndicatorConfiguration,
            callReadinessStrategy: .leadTime(minutes: 15)
        )

        XCTAssertNil(resolution.accessory)
        XCTAssertNil(resolution.readyCallEvent)
    }

    func testDisabledIndicatorFallsBackToCallReadinessStrategyAndReturnsCallIconAccessory() {
        let meeting = event("Standup", "10:00", "10:30", videoService: .zoom, videoURL: "https://zoom.us/j/1")
        let resolution = resolveMenuBarAccessory(
            events: [meeting], on: date(0), now: date(9, 50), calendar: calendar,
            indicatorConfiguration: disabledIndicatorConfiguration,
            callReadinessStrategy: .leadTime(minutes: 15)
        )

        guard case .callIcon(let service) = resolution.accessory else {
            return XCTFail("expected a call-icon accessory")
        }
        XCTAssertEqual(service, .zoom)
        XCTAssertEqual(resolution.readyCallEvent?.id, "Standup")
    }

    func testDisabledIndicatorWithNothingReadyReturnsNilAccessoryAndNilReadyCallEvent() {
        let meeting = event("Standup", "10:00", "10:30", videoService: .zoom, videoURL: "https://zoom.us/j/1")
        let resolution = resolveMenuBarAccessory(
            events: [meeting], on: date(0), now: date(8, 0), calendar: calendar,
            indicatorConfiguration: disabledIndicatorConfiguration,
            callReadinessStrategy: .leadTime(minutes: 15)
        )

        XCTAssertNil(resolution.accessory)
        XCTAssertNil(resolution.readyCallEvent)
    }
}
