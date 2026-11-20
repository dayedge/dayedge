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
                         status: EventStatus = .confirmed, allDay: Bool = false,
                         response: EventAttendee.Status? = nil) -> AgendaEventModel {
        AgendaEventModel(
            id: title,
            startTime: allDay ? nil : "x", endTime: allDay ? nil : "y",
            startDate: start, endDate: start.addingTimeInterval(Double(minutes) * 60),
            title: title, status: status,
            videoService: link ? .zoom : nil,
            videoURL: link ? "https://zoom.us/j/1" : nil,
            myResponseStatus: response
        )
    }

    private var dates: DatePresentationFormatter {
        DatePresentationFormatter(regionalLocale: Locale(identifier: "en_US"), displayLocale: Locale(identifier: "en"),
                                  calendar: calendar)
    }

    private func titles(
        now: Date,
        events: [AgendaEventModel] = [],
        tasks: Int = 0,
        muted: Set<String> = [],
        globalMute: (Date, PauseChoice?)? = nil
    ) -> [[String]] {
        StatusMenuPlan.resolve(.init(
            now: now, calendar: calendar, events: events, actionableTaskCount: tasks,
            isMuted: { muted.contains($0.id) },
            globalMute: globalMute.map { (until: $0.0, chosen: $0.1) },
            dates: dates, timeFormat: .twentyFourHour
        )).map { $0.map(\.title) }
    }

    private func pausedTitle(now: Date, until: Date, timeFormat: TimeFormat = .twentyFourHour) -> String {
        StatusMenuPlan.pausedTitle(until: until, chosen: nil, now: now, dates: dates, timeFormat: timeFormat)
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
                            globalMute: (at(18), .duration(.evening)))
        XCTAssertEqual(result, [
            top,
            ["Join “1F – Proces wytwórczy”", "Show Today’s Tasks (3)"],
            ["Meeting Alerts Paused · Until 18:00"],
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
            .muteMeeting(event), .restoreMeeting(event), .pauseAlerts([], pausedTitle: nil), .pauseAlerts([], pausedTitle: "Paused"),
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
        func pause(now: Date, until: Date, chosen: MuteUntilOption?) -> (isPaused: Bool, checked: PauseChoice?)? {
            let menu = pauseRow(now: now, globalMute: (until, chosen.map(PauseChoice.duration)))
            return menu.map { ($0.pausedTitle != nil, $0.checked) }
        }
        XCTAssertEqual(pause(now: at(15), until: at(18), chosen: .evening)?.checked, .duration(.evening), "a daypart still ends there")
        XCTAssertEqual(pause(now: at(15), until: at(8, daysAhead: 1), chosen: .tomorrow)?.checked, .duration(.tomorrow))
        XCTAssertNil(pause(now: at(9, 30), until: at(10, 10), chosen: .oneHour)?.checked, "an hour from now is later")
        XCTAssertNil(pause(now: at(9, 30), until: at(10, 10), chosen: nil)?.checked)
        XCTAssertEqual(pause(now: at(9, 30), until: at(10, 10), chosen: .oneHour)?.isPaused, true)
        XCTAssertEqual(StatusMenuItem.unmuteAll.title, "Resume Meeting Alerts")
        XCTAssertNil(StatusMenuItem.unmuteAll.symbolName, "text only, like the durations")
        XCTAssertNil(StatusMenuItem.pause(.duration(.oneHour), title: "For 1 Hour", checked: false).symbolName)
    }

    // MARK: - Until the meeting ends

    /// The Pause Meeting Alerts row and its submenu.
    private struct PauseRow {
        var choices: [(choice: PauseChoice, title: String, checked: Bool)] = []
        var pausedTitle: String?

        var meeting: (choice: PauseChoice, title: String, checked: Bool)? {
            choices.first { if case .meetingEnd = $0.choice { true } else { false } }
        }
        var checked: PauseChoice? { choices.first(where: \.checked)?.choice }
    }

    private func pauseRow(now: Date, events: [AgendaEventModel] = [], globalMute: (Date, PauseChoice?)? = nil) -> PauseRow? {
        let rows = StatusMenuPlan.resolve(.init(now: now, calendar: calendar, events: events, actionableTaskCount: 0,
                                                isMuted: { _ in false }, globalMute: globalMute.map { (until: $0.0, chosen: $0.1) },
                                                dates: dates, timeFormat: .twentyFourHour))
        for row in rows.joined() {
            guard case .pauseAlerts(let items, let pausedTitle) = row else { continue }
            var pause = PauseRow(pausedTitle: pausedTitle)
            for case .pause(let choice, let title, let checked) in items { pause.choices.append((choice, title, checked)) }
            return pause
        }
        return nil
    }

    func testMeetingInProgressCanPauseAlertsUntilItEnds() {
        let review = meeting("Design Review", at(10), minutes: 60)
        let row = pauseRow(now: at(10, 15), events: [review])
        XCTAssertEqual(row?.meeting?.title, "Until “Design Review” Ends (11:00)")
        XCTAssertEqual(row?.choices.first?.choice, .meetingEnd(title: "Design Review", end: at(11)), "first, above the durations")
    }

    func testUpcomingMeetingIsNotOfferedForPausing() {
        XCTAssertNil(pauseRow(now: at(9), events: [meeting("Design Review", at(10))])?.meeting)
    }

    func testMeetingEndingWithinMinutesIsNotOfferedForPausing() {
        XCTAssertNil(pauseRow(now: at(10, 26), events: [meeting("Design Review", at(10))])?.meeting)
    }

    func testMeetingEndingOnAnotherDayIsNotOfferedForPausing() {
        XCTAssertNil(pauseRow(now: at(23), events: [meeting("Offsite", at(22), minutes: 180)])?.meeting)
    }

    func testDeclinedMeetingIsNotOfferedForPausing() {
        XCTAssertNil(pauseRow(now: at(10, 5), events: [meeting("Design Review", at(10), response: .declined)])?.meeting)
    }

    func testTentativeMeetingIsOfferedForPausing() {
        let review = meeting("Design Review", at(10), status: .tentative, response: .tentative)
        XCTAssertNotNil(pauseRow(now: at(10, 5), events: [review])?.meeting)
    }

    func testOverlappingMeetingsPauseUntilTheLatestStartedEnds() {
        let events = [meeting("Planning", at(10), minutes: 60), meeting("Sync", at(10, 30), minutes: 90)]
        XCTAssertEqual(pauseRow(now: at(10, 45), events: events)?.meeting?.choice, .meetingEnd(title: "Sync", end: at(12)))
    }

    func testMeetingIsOfferedWhileAlreadyPaused() {
        let events = [meeting("Design Review", at(10), minutes: 60)]
        XCTAssertNotNil(pauseRow(now: at(10, 15), events: events, globalMute: (at(18), .duration(.evening)))?.meeting)
    }

    func testPauseFromTheMeetingIsCheckedAndNamesIt() {
        let events = [meeting("Design Review", at(10), minutes: 60)]
        let choice = PauseChoice.meetingEnd(title: "Design Review", end: at(11))
        let row = pauseRow(now: at(10, 15), events: events, globalMute: (at(11), choice))
        XCTAssertEqual(row?.checked, choice)
        XCTAssertEqual(row?.pausedTitle, "Meeting Alerts Paused · Until “Design Review” Ends")
    }

    func testMovedMeetingNoLongerChecksItsPause() {
        let events = [meeting("Design Review", at(10), minutes: 90)]
        let row = pauseRow(now: at(10, 15), events: events,
                           globalMute: (at(11), .meetingEnd(title: "Design Review", end: at(11))))
        XCTAssertNil(row?.checked, "the pause still ends at 11:00, the meeting now later")
    }

    func testRelevantMeetingSkipsDeclined() {
        let events = [meeting("Declined", at(10, 30), response: .declined), meeting("Planning", at(10), minutes: 60)]
        XCTAssertEqual(StatusMenuPlan.relevantMeeting(in: events, now: at(10, 40))?.id, "Planning")
    }

    // MARK: - Shortened titles

    func testShortTitleIsKeptWhole() {
        XCTAssertEqual(StatusMenuPlan.quoted("  Standup  ", limit: 30), "“Standup”")
    }

    func testTitleIsFlattenedToOneLine() {
        XCTAssertEqual(StatusMenuPlan.quoted("Design\n\tReview", limit: 30), "“Design Review”")
    }

    func testLongTitleIsCutOnAWordBreak() {
        let title = StatusMenuPlan.quoted("Quarterly planning with the platform and design teams", limit: 30)
        XCTAssertEqual(title, "“Quarterly planning with the…”")
    }

    func testLongTitleDropsPunctuationBeforeTheEllipsis() {
        XCTAssertEqual(StatusMenuPlan.quoted("Retro, planning, demos, and everything else", limit: 24), "“Retro, planning, demos…”")
    }

    func testLongWordIsCutMidWordWithoutSplittingCharacters() {
        let title = StatusMenuPlan.quoted(String(repeating: "👩‍💻", count: 40), limit: 30)
        XCTAssertEqual(title, "“" + String(repeating: "👩‍💻", count: 29) + "…”")
    }

    // MARK: - When alerts resume

    func testPausedTitleTodayShowsOnlyTheTime() {
        XCTAssertEqual(pausedTitle(now: at(9), until: at(14)), "Meeting Alerts Paused · Until 14:00")
    }

    func testPausedTitleForOneHourShowsTheResolvedTime() {
        let now = at(9, 10)
        let until = MuteUntilOption.oneHour.endDate(now: now, calendar: calendar)
        XCTAssertEqual(pausedTitle(now: now, until: until), "Meeting Alerts Paused · Until 10:10")
    }

    func testPausedTitleTomorrowNamesTheDay() {
        XCTAssertEqual(pausedTitle(now: at(15), until: at(8, daysAhead: 1)), "Meeting Alerts Paused · Until Tomorrow, 08:00")
    }

    func testPausedTitleLaterWritesTheDate() {
        XCTAssertEqual(pausedTitle(now: at(15), until: at(8, daysAhead: 2)), "Meeting Alerts Paused · Until Fri, Oct 2, 08:00")
    }

    /// Polish says "until tomorrow" with its own form ("do jutra"), so each case is a whole sentence.
    func testPausedTitleInPolish() {
        let polish = DatePresentationFormatter(regionalLocale: Locale(identifier: "pl_PL"), displayLocale: Locale(identifier: "pl"),
                                               calendar: calendar)
        func title(_ until: Date) -> String {
            StatusMenuPlan.pausedTitle(until: until, chosen: nil, now: at(15), dates: polish, timeFormat: .twentyFourHour)
        }
        XCTAssertEqual(title(at(18)), "Alerty spotkań wstrzymane · do 18:00")
        XCTAssertEqual(title(at(8, daysAhead: 1)), "Alerty spotkań wstrzymane · do jutra, 08:00")
        let later = at(8, daysAhead: 2)
        XCTAssertEqual(title(later), "Alerty spotkań wstrzymane · do \(polish.menuBarDate(later)), 08:00")
    }

    func testPausedTitleFollowsTheTwelveHourSetting() {
        XCTAssertEqual(pausedTitle(now: at(15), until: at(18), timeFormat: .twelveHour), "Meeting Alerts Paused · Until 6:00pm")
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
