import AppKit
import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class StatusMenuPlanTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func at(_ hour: Int, _ minute: Int = 0, daysAhead: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let day = calendar.date(byAdding: .day, value: daysAhead, to: base)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func meeting(_ title: String, _ start: Date, minutes: Int = 30, link: Bool = true,
                         status: EventStatus = .confirmed, allDay: Bool = false) -> AgendaEventModel {
        AgendaEventModel(
            id: title,
            startTime: allDay ? nil : "x", endTime: allDay ? nil : "y",
            startDate: start, endDate: start.addingTimeInterval(Double(minutes) * 60),
            title: title, status: status,
            videoService: link ? .zoom : nil,
            videoURL: link ? "https://zoom.us/j/1" : nil
        )
    }

    private func titles(
        now: Date,
        events: [AgendaEventModel] = [],
        tasks: Int = 0,
        muted: Set<String> = [],
        globalMute: (Date, MuteUntilOption?)? = nil
    ) -> [[String]] {
        StatusMenuPlan.resolve(.init(
            now: now, calendar: calendar, events: events, actionableTaskCount: tasks,
            isMuted: { muted.contains($0.id) },
            globalMute: globalMute.map { (until: $0.0, chosen: $0.1) }
        )).map { $0.map(\.title) }
    }

    private let top = ["Open DayEdge", "Search…", "Ask DayEdge…"]
    private let app = ["Settings…", "About DayEdge"]
    private let quit = ["Quit DayEdge"]

    // MARK: - The spec's examples

    func testRichContext() {
        XCTAssertEqual(titles(now: at(10, 35), events: [meeting("PZU 1f Daily", at(10, 30))], tasks: 3), [
            top,
            ["Join “PZU 1f Daily”", "Mute This Meeting", "Show Today’s Tasks (3)"],
            ["Pause Meeting Alerts"],
            app, quit
        ])
    }

    func testCurrentMeetingWhileGloballyMuted() {
        let result = titles(now: at(15, 20), events: [meeting("1F – Proces wytwórczy", at(15, 15))], tasks: 3,
                            globalMute: (at(18), .evening))
        XCTAssertEqual(result, [
            top,
            ["Join “1F – Proces wytwórczy”", "Show Today’s Tasks (3)"],
            ["Meeting Alerts Paused"],
            app, quit
        ], "the global mute outranks the meeting's own")
    }

    func testOnlyTheMeetingMuted() {
        XCTAssertEqual(titles(now: at(10), events: [meeting("PZU 1f Daily", at(10, 30))], muted: ["PZU 1f Daily"]), [
            top,
            ["Join “PZU 1f Daily”", "Unmute This Meeting"],
            ["Pause Meeting Alerts"],
            app, quit
        ])
    }

    func testNothingGoingOnLeavesNoEmptyRows() {
        XCTAssertEqual(titles(now: at(10)), [top, ["Pause Meeting Alerts"], app, quit])
    }

    func testTasksButNoMeeting() {
        XCTAssertEqual(titles(now: at(10), tasks: 3), [top, ["Show Today’s Tasks (3)"], ["Pause Meeting Alerts"], app, quit])
    }

    func testMeetingButNoTasks() {
        XCTAssertEqual(titles(now: at(10), events: [meeting("PZU 1f Daily", at(10, 30))]), [
            top, ["Join “PZU 1f Daily”", "Mute This Meeting"], ["Pause Meeting Alerts"], app, quit
        ])
    }

    // MARK: - Choosing the one meeting

    func testCurrentBeatsUpcomingAndLatestStartedWinsATie() {
        let events = [
            meeting("Long", at(9), minutes: 180),
            meeting("Standup", at(10, 30)),
            meeting("Later", at(11, 30))
        ]
        XCTAssertEqual(StatusMenuPlan.relevantMeeting(in: events, now: at(10, 40))?.title, "Standup")
        XCTAssertEqual(StatusMenuPlan.relevantMeeting(in: events, now: at(8))?.title, "Long")
        XCTAssertEqual(StatusMenuPlan.relevantMeeting(in: events, now: at(12, 30))?.title, nil)
    }

    func testCancelledDeclinedAndAllDayAreSkipped() {
        let events = [
            meeting("Holiday", at(0), minutes: 24 * 60, allDay: true),
            meeting("Declined", at(10, 30), status: .cancelled),
            meeting("Review", at(11))
        ]
        XCTAssertEqual(StatusMenuPlan.relevantMeeting(in: events, now: at(10, 35))?.title, "Review")
    }

    func testAMeetingWithoutALinkIsShownInsteadOfJoined() {
        let result = titles(now: at(10), events: [meeting("Design Review", at(11), link: false)])
        XCTAssertEqual(result[1], ["Show “Design Review” in Calendar", "Mute This Meeting"])
    }

    func testEveryRowButQuitHasASystemSymbol() {
        let event = meeting("Review", at(11))
        let rows: [StatusMenuItem] = [
            .open, .search, .ask, .join(event), .showEvent(event, day: at(0)), .showTodayTasks(count: 2),
            .muteMeeting(event), .restoreMeeting(event), .pauseAlerts([.oneHour], isPaused: false, checked: nil), .pauseAlerts([.oneHour], isPaused: true, checked: nil),
            .settings, .about
        ]
        for row in rows {
            let name = try? XCTUnwrap(row.symbolName, row.title)
            XCTAssertNotNil(name.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }, "\(row.title): \(name ?? "-")")
        }
        XCTAssertNil(StatusMenuItem.quit.symbolName)
    }

    func testLongTitlesAreShortened() {
        let long = String(repeating: "a", count: 80)
        let title = StatusMenuItem.join(meeting(long, at(10))).title
        XCTAssertTrue(title.hasSuffix("…”"))
        XCTAssertLessThan(title.count, 50)
    }

    // MARK: - Mute Until

    func testDaypartsThatHavePassedAreNotOffered() {
        XCTAssertEqual(MuteUntilOption.available(now: at(9), calendar: calendar), [.oneHour, .afternoon, .evening, .tomorrow])
        XCTAssertEqual(MuteUntilOption.available(now: at(13, 45), calendar: calendar), [.oneHour, .evening, .tomorrow],
                       "the afternoon starting in 15 minutes isn't worth offering")
        XCTAssertEqual(MuteUntilOption.available(now: at(15), calendar: calendar), [.oneHour, .evening, .tomorrow])
        XCTAssertEqual(MuteUntilOption.available(now: at(20), calendar: calendar), [.oneHour, .tomorrow])
    }

    func testDaypartEnds() {
        let now = at(9, 10)
        XCTAssertEqual(MuteUntilOption.oneHour.endDate(now: now, calendar: calendar), at(10, 10))
        XCTAssertEqual(MuteUntilOption.afternoon.endDate(now: now, calendar: calendar), at(14))
        XCTAssertEqual(MuteUntilOption.evening.endDate(now: now, calendar: calendar), at(18))
        XCTAssertEqual(MuteUntilOption.tomorrow.endDate(now: now, calendar: calendar), at(8, daysAhead: 1))
        XCTAssertEqual(MuteUntilOption.tomorrow.endDate(now: at(23, 50), calendar: calendar), at(8, daysAhead: 1))
    }

    func testPausedAlertsCheckTheChoiceOnlyWhileItStillMeansThisPause() {
        func pause(now: Date, until: Date, chosen: MuteUntilOption?) -> (isPaused: Bool, checked: MuteUntilOption?)? {
            let rows = StatusMenuPlan.resolve(.init(now: now, calendar: calendar, events: [], actionableTaskCount: 0,
                                                    isMuted: { _ in false }, globalMute: (until, chosen)))
            for row in rows.joined() { if case .pauseAlerts(_, let isPaused, let checked) = row { return (isPaused, checked) } }
            return nil
        }
        XCTAssertEqual(pause(now: at(15), until: at(18), chosen: .evening)?.checked, .evening, "a daypart still ends there")
        XCTAssertEqual(pause(now: at(15), until: at(8, daysAhead: 1), chosen: .tomorrow)?.checked, .tomorrow)
        XCTAssertNil(pause(now: at(9, 30), until: at(10, 10), chosen: .oneHour)?.checked, "an hour from now is later")
        XCTAssertNil(pause(now: at(9, 30), until: at(10, 10), chosen: nil)?.checked)
        XCTAssertEqual(pause(now: at(9, 30), until: at(10, 10), chosen: .oneHour)?.isPaused, true)
        XCTAssertEqual(StatusMenuItem.unmuteAll.title, "Resume Meeting Alerts")
        XCTAssertNil(StatusMenuItem.unmuteAll.symbolName, "text only, like the durations")
    }

    // MARK: - Today's tasks

    func testActionableTasksAreOverdueOrDueTodayOnly() {
        func task(_ id: String, due: Date?, priority: TaskPriority = .none, done: Bool = false) -> TaskItem {
            TaskItem(id: id, title: id, listID: "w", dueDate: due, hasDueTime: false, priority: priority,
                     isCompleted: done, completionDate: nil)
        }
        let tasks = [
            task("overdue", due: at(9, daysAhead: -2)),
            task("today", due: at(0)),
            task("tomorrow", due: at(0, daysAhead: 1)),
            task("undated urgent", due: nil, priority: .high),
            task("done today", due: at(0), done: true)
        ]
        XCTAssertEqual(TaskBuckets.actionableTodayCount(tasks: tasks, now: at(12), calendar: calendar), 2)
    }
}
