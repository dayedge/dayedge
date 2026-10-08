import XCTest
@testable import Shell
@testable import Domain
@testable import Platform

@MainActor
final class CalendarPermissionMonitorTests: XCTestCase {
    func testReportsEachChangeOnceAndNothingOtherwise() {
        var system = SourceAccessStatus.granted
        let monitor = CalendarPermissionMonitor(read: { system })
        var reported: [SourceAccessStatus] = []
        monitor.onChange = { reported.append($0) }

        monitor.check()
        XCTAssertEqual(reported, [], "unchanged")

        system = .denied
        monitor.check()
        monitor.check()
        XCTAssertEqual(reported, [.denied])
        XCTAssertFalse(monitor.isGranted)

        system = .granted
        monitor.check()
        XCTAssertEqual(reported, [.denied, .granted])
        XCTAssertTrue(monitor.isGranted)
    }

    func testStartsFromThePermissionAsItIsNow() {
        let monitor = CalendarPermissionMonitor(read: { .denied })
        XCTAssertEqual(monitor.status, .denied)
    }

    func testNoticesARevocationWithoutBeingAsked() async throws {
        var system = SourceAccessStatus.granted
        let monitor = CalendarPermissionMonitor(read: { system }, interval: .milliseconds(20))
        var reported: [SourceAccessStatus] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()
        defer { monitor.stop() }

        system = .denied
        for _ in 0..<50 where reported.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(reported, [.denied])
    }
}
