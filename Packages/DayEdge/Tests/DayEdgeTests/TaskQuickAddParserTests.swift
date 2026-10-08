import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// Quick Add parsing. Reference: Wednesday 2026-09-23 12:00, Monday-first
/// week, host time zone (like `ChronoBaselineTests`). Lists: Work, Personal,
/// Home.
final class TaskQuickAddParserTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }()
    private var reference: Date { day(2026, 9, 23, hour: 12) }
    private let lists = [QuickAddList(id: "work", title: "Work"), QuickAddList(id: "personal", title: "Personal"),
                         QuickAddList(id: "home", title: "Home")]

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func parse(_ text: String) async -> QuickAddDraft {
        await QuickAddParser().parse(text, lists: lists, referenceDate: reference, calendar: calendar)
    }

    private func stage(_ text: String) async -> QuickAddDraft? {
        await TaskQuickAddStage(lists: { [lists] in lists }).resolve(text, referenceDate: reference, calendar: calendar)
    }

    // MARK: - The three core sentences

    func testWeekNarrowedByAWeekdayWithTypos() async throws {
        let draft = try await XCTUnwrapAsync(await stage("invoid next week on frida"))
        XCTAssertEqual(draft.title, "Invoid", "titles aren't spell-corrected")
        XCTAssertEqual(draft.day, day(2026, 10, 2), "Friday of next week")
        XCTAssertNil(draft.startTime)
    }

    func testTimeRangeAndDayMonth() async throws {
        let draft = try await XCTUnwrapAsync(await stage("10am - 11am dentist with Adrien 10 sept"))
        XCTAssertEqual(draft.title, "Dentist with Adrien")
        XCTAssertEqual(draft.day, day(2027, 9, 10), "the next 10 September")
        XCTAssertEqual(draft.startTime?.hour, 10)
        XCTAssertEqual(draft.endTime?.hour, 11)
    }

    func testEverythingAtOnceInAnyPosition() async throws {
        let draft = try await XCTUnwrapAsync(await stage("10 am next week send invoice #work !!"))
        XCTAssertEqual(draft.title, "Send invoice")
        XCTAssertEqual(draft.day, day(2026, 9, 28), "next week = its Monday")
        XCTAssertEqual(draft.startTime?.hour, 10)
        XCTAssertEqual(draft.listID, "work")
        XCTAssertEqual(draft.priority, .medium, "!! is medium, as in Reminders")
        let task = draft.taskDraft(calendar: calendar)
        XCTAssertEqual(task.dueDate, day(2026, 9, 28, hour: 10))
        XCTAssertTrue(task.hasDueTime)
    }

    // MARK: - Navigation stays navigation

    func testPureDatesAndBareWordsAreNotTasks() async {
        for text in ["tomorrow", "next week", "Friday", "October", "3pm", "Work"] {
            let result = await stage(text)
            XCTAssertNil(result, "\"\(text)\" should not become a task (got \(String(describing: result?.title)))")
        }
    }

    func testWeekFirstAndDayOfMonthPhrases() async throws {
        let cases: [(String, Date, Int?)] = [
            ("pay rent next week mon", day(2026, 9, 28), nil),
            ("pay rent next week monday 10am", day(2026, 9, 28), 10),
            ("pay rent next month 12", day(2026, 10, 12), nil),
            ("pay rent 12th next month", day(2026, 10, 12), nil),
            ("pay rent the 3rd of next month", day(2026, 10, 3), nil),
            ("pay rent next month 12 at 10am", day(2026, 10, 12), 10)
        ]
        for (text, expectedDay, hour) in cases {
            let draft = try await XCTUnwrapAsync(await stage(text))
            XCTAssertEqual(draft.title, "Pay rent", text)
            XCTAssertEqual(draft.day, expectedDay, text)
            XCTAssertEqual(draft.startTime?.hour, hour, text)
        }
        // Offsets and week numbers in tasks.
        let offsets: [(String, Date)] = [
            ("pay rent in 3 weeks", day(2026, 10, 14)),
            ("pay rent in two weeks", day(2026, 10, 7)),
            ("pay rent 10 days from now", day(2026, 10, 3)),
            ("pay rent week 42", day(2026, 10, 12)),
            ("pay rent week 42 friday", day(2026, 10, 16))
        ]
        for (text, expectedDay) in offsets {
            let draft = try await XCTUnwrapAsync(await stage(text))
            XCTAssertEqual(draft.title, "Pay rent", text)
            XCTAssertEqual(draft.day, expectedDay, text)
        }
        // A number that isn't the day of a month phrase isn't taken by it.
        let eggs = try await XCTUnwrapAsync(await stage("buy 12 eggs next week mon"))
        XCTAssertEqual(eggs.title, "Buy 12 eggs")
        XCTAssertEqual(eggs.day, day(2026, 9, 28))
    }

    /// Time spans (reference Wed 23 Sep 2026, 12:00): every row is
    /// "phrase → title | day | start–end".
    func testTimeSpans() async throws {
        let cases: [(String, String, Date, String, String?)] = [
            // Bare hours under 13 beside a day
            ("daily 11-12 today", "Daily", day(2026, 9, 23), "11:00", "12:00"),
            ("standup tomorrow 10-11", "Standup", day(2026, 9, 24), "10:00", "11:00"),
            ("workshop friday 9-5", "Workshop", day(2026, 9, 25), "09:00", "17:00"),
            ("review 3-4 tomorrow", "Review", day(2026, 9, 24), "15:00", "16:00"),
            ("sync tomorrow 10 to 11", "Sync", day(2026, 9, 24), "10:00", "11:00"),
            ("sync 10-11 next week tue", "Sync", day(2026, 9, 29), "10:00", "11:00"),
            ("standup starting next week tue 11-12", "Standup", day(2026, 9, 29), "11:00", "12:00"),
            // Durations
            ("lunch tomorrow 1pm for 1h", "Lunch", day(2026, 9, 24), "13:00", "14:00"),
            ("lunch tomorrow 1pm for 90 min", "Lunch", day(2026, 9, 24), "13:00", "14:30"),
            ("lunch tomorrow at 1pm for 2 hours", "Lunch", day(2026, 9, 24), "13:00", "15:00"),
            ("lunch tomorrow 13:00 1h", "Lunch", day(2026, 9, 24), "13:00", "14:00"),
            ("review tomorrow 10:00 1.5h", "Review", day(2026, 9, 24), "10:00", "11:30"),
            ("review tomorrow at 10 for 1h30", "Review", day(2026, 9, 24), "10:00", "11:30"),
            // 24-hour and shared am/pm ranges
            ("lunch tomorrow 13-14", "Lunch", day(2026, 9, 24), "13:00", "14:00"),
            ("standup tomorrow 9:30-9:45", "Standup", day(2026, 9, 24), "09:30", "09:45"),
            ("lunch tomorrow 1-2pm", "Lunch", day(2026, 9, 24), "13:00", "14:00"),
            ("lunch tomorrow noon-1pm", "Lunch", day(2026, 9, 24), "12:00", "13:00"),
            ("sync tomorrow 13:00->14:30", "Sync", day(2026, 9, 24), "13:00", "14:30"),
            ("sync tomorrow 1pm~2pm", "Sync", day(2026, 9, 24), "13:00", "14:00"),
            ("sync tomorrow 1pm–2:30pm", "Sync", day(2026, 9, 24), "13:00", "14:30"),
            // Range words
            ("lunch tomorrow between 1 and 2pm", "Lunch", day(2026, 9, 24), "13:00", "14:00"),
            ("workshop tomorrow from 9 till 11", "Workshop", day(2026, 9, 24), "09:00", "11:00"),
            ("workshop tomorrow 9am thru 11am", "Workshop", day(2026, 9, 24), "09:00", "11:00"),
            ("workshop tomorrow 9am untill 11am", "Workshop", day(2026, 9, 24), "09:00", "11:00"),
            ("workshop tomorrow from 9 to 5", "Workshop", day(2026, 9, 24), "09:00", "17:00"),
            ("workshop tomorrow from 11 to 1", "Workshop", day(2026, 9, 24), "11:00", "13:00"),
            // The afternoon rule and spoken times
            ("call at 3", "Call", day(2026, 9, 23), "15:00", nil),
            ("call tomorrow at 3", "Call", day(2026, 9, 24), "15:00", nil),
            ("call tomorrow at 8", "Call", day(2026, 9, 24), "08:00", nil),
            ("call tomorrow at 07:00", "Call", day(2026, 9, 24), "07:00", nil),
            ("call tomorrow at half past 2", "Call", day(2026, 9, 24), "14:30", nil),
            ("call tomorrow quarter to 4", "Call", day(2026, 9, 24), "15:45", nil),
            ("call tomorrow at 2.30pm", "Call", day(2026, 9, 24), "14:30", nil),
            ("call tomorrow at 14.30", "Call", day(2026, 9, 24), "14:30", nil),
            ("call tomorrow at noon", "Call", day(2026, 9, 24), "12:00", nil),
            ("call at 11", "Call", day(2026, 9, 24), "11:00", nil),  // 11:00 already passed: tomorrow
            // Parts of the day (approximate) — a stated time wins
            ("workshop tomorrow morning", "Workshop", day(2026, 9, 24), "09:00", nil),
            ("workshop tomorrow evening", "Workshop", day(2026, 9, 24), "18:00", nil),
            ("workshop tomorrow morning at 10:30", "Workshop", day(2026, 9, 24), "10:30", nil),
            // From a time, no end
            ("workshop tomorrow from 1pm", "Workshop", day(2026, 9, 24), "13:00", nil)
        ]
        for (text, title, expectedDay, start, end) in cases {
            let draft = try await XCTUnwrapAsync(await stage(text))
            let hm = { (c: DateComponents?) in c.map { String(format: "%02d:%02d", $0.hour ?? 0, $0.minute ?? 0) } }
            XCTAssertEqual(draft.title, title, text)
            XCTAssertEqual(draft.day, expectedDay, text)
            XCTAssertEqual(hm(draft.startTime), start, text)
            XCTAssertEqual(hm(draft.endTime), end, text)
        }
        // Plain numbers that aren't times stay in the title.
        let pages = try await XCTUnwrapAsync(await stage("read pages 3-5 tomorrow"))
        XCTAssertEqual(pages.title, "Read pages 3-5")
        XCTAssertNil(pages.startTime)
        let apples = try await XCTUnwrapAsync(await stage("buy 10 apples tomorrow"))
        XCTAssertEqual(apples.title, "Buy 10 apples")
        XCTAssertNil(apples.startTime)
    }

    /// Day spans and "all day" (reference Wed 23 Sep 2026): the start is the
    /// draft's day, the end its `endDay`; a span without times is all day.
    func testDaySpans() async throws {
        let cases: [(String, String, Date, Date?, Bool)] = [
            ("trip fri-sun", "Trip", day(2026, 9, 25), day(2026, 9, 27), true),
            ("trip friday to sunday", "Trip", day(2026, 9, 25), day(2026, 9, 27), true),
            ("trip mon thru wed", "Trip", day(2026, 9, 28), day(2026, 9, 30), true),
            ("trip sat - tue", "Trip", day(2026, 9, 26), day(2026, 9, 29), true),
            ("trip 3-5 oct", "Trip", day(2026, 10, 3), day(2026, 10, 5), true),
            ("trip 3–5 October", "Trip", day(2026, 10, 3), day(2026, 10, 5), true),
            ("trip oct 3-5", "Trip", day(2026, 10, 3), day(2026, 10, 5), true),
            ("trip from 3 oct to 5 oct", "Trip", day(2026, 10, 3), day(2026, 10, 5), true),
            ("trip from oct 30 to nov 2", "Trip", day(2026, 10, 30), day(2026, 11, 2), true),
            ("trip 30 dec - 2 jan", "Trip", day(2026, 12, 30), day(2027, 1, 2), true),
            ("trip 1-3 sept", "Trip", day(2027, 9, 1), day(2027, 9, 3), true),   // already past this year
            ("trip this weekend", "Trip", day(2026, 9, 26), day(2026, 9, 27), true),
            ("trip over the weekend", "Trip", day(2026, 9, 26), day(2026, 9, 27), true),
            ("trip next weekend", "Trip", day(2026, 10, 3), day(2026, 10, 4), true),
            ("offsite tomorrow all day", "Offsite", day(2026, 9, 24), nil, true),
            ("offsite friday all day", "Offsite", day(2026, 9, 25), nil, true)
        ]
        for (text, title, start, end, allDay) in cases {
            let draft = try await XCTUnwrapAsync(await stage(text))
            XCTAssertEqual(draft.title, title, text)
            XCTAssertEqual(draft.day, start, text)
            XCTAssertEqual(draft.endDay, end, text)
            XCTAssertEqual(draft.isAllDay, allDay, text)
            XCTAssertNil(draft.startTime, text)
        }
        // A span with times is not all day; its times stay.
        let workshop = try await XCTUnwrapAsync(await stage("workshop mon-wed 9-17"))
        XCTAssertEqual(workshop.day, day(2026, 9, 28))
        XCTAssertEqual(workshop.endDay, day(2026, 9, 30))
        XCTAssertFalse(workshop.isAllDay)
        XCTAssertEqual(workshop.startTime?.hour, 9)
        XCTAssertEqual(workshop.endTime?.hour, 17)
        // A duration is kept as stated.
        let review = try await XCTUnwrapAsync(await stage("review tomorrow 10:00 for 90 min"))
        XCTAssertEqual(review.duration, 90)
        // Not spans: an invalid day, numbers without a month, a lone day.
        let invalid = await parse("trip 30-31 nov")  // no 31 November: no date, so not a task either
        XCTAssertNil(invalid.endDay)
        XCTAssertNil(invalid.day)
        let pages = try await XCTUnwrapAsync(await stage("read pages 3-5 tomorrow"))
        XCTAssertNil(pages.endDay)
        XCTAssertEqual(pages.title, "Read pages 3-5")
    }

    /// "every second Friday", "on the last day", spelled counts, and one
    /// rule per task.
    func testRecurrenceEdgeCases() async throws {
        let biweekly = try await XCTUnwrapAsync(await stage("submit timesheet every second Friday"))
        XCTAssertEqual(biweekly.title, "Submit timesheet")
        XCTAssertEqual(biweekly.recurrence?.frequency, .weekly)
        XCTAssertEqual(biweekly.recurrence?.interval, 2)
        XCTAssertEqual(biweekly.recurrence?.weekdays.map(\.weekday), [6])
        XCTAssertEqual(biweekly.day, day(2026, 9, 25))

        let other = try await XCTUnwrapAsync(await stage("team sync every other tue"))
        XCTAssertEqual(other.title, "Team sync")
        XCTAssertEqual(other.recurrence?.interval, 2)
        XCTAssertEqual(other.recurrence?.weekdays.map(\.weekday), [3])

        let lastDay = try await XCTUnwrapAsync(await stage("review goals every month on the last day"))
        XCTAssertEqual(lastDay.title, "Review goals")
        XCTAssertEqual(lastDay.recurrence?.daysOfMonth, [-1])

        let spelled = try await XCTUnwrapAsync(await stage("change filter every six months"))
        XCTAssertEqual(spelled.title, "Change filter")
        XCTAssertEqual(spelled.recurrence?.frequency, .monthly)
        XCTAssertEqual(spelled.recurrence?.interval, 6)

        let report = try await XCTUnwrapAsync(await stage("every Friday send weekly report"))
        XCTAssertEqual(report.title, "Send weekly report", "a second rule word is part of the title")
        XCTAssertEqual(report.recurrence?.weekdays.map(\.weekday), [6])
        XCTAssertEqual(report.day, day(2026, 9, 25))
    }

    /// Event or task: forced, hard signals, soft order, a day, no day.
    func testEventOrTaskDecision() async {
        let calendars = [QuickAddList(id: "cal-work", title: "Work"), QuickAddList(id: "cal-family", title: "Family")]
        let cases: [(String, [QuickAddKind])] = [
            // 1. Said outright.
            ("lunch friday 1pm t:t", [.task]),
            ("pay rent friday t:e", [.event]),
            ("+ standup 13-14", [.task]),
            ("dentist type:event", [.event]),
            // 2. Hard signals.
            ("standup 13-14", [.event]),
            ("standup 10:00-11:00", [.event]),
            ("workshop friday 9 to 5", [.event]),
            ("call with Anna tomorrow 3pm for 30 min", [.event]),
            ("conference 3-5 oct", [.event]),
            ("offsite friday all day", [.event]),
            ("trip over the weekend", [.event]),
            ("pay rent friday !!", [.task]),
            ("review deck tomorrow 10am-11am !!", [.task, .event]),
            // 3. Soft signals pick the order.
            ("coffee tomorrow at Starbucks", [.event, .task]),
            ("dinner friday #family", [.event, .task]),
            ("call bank tomorrow 10am #work", [.event, .task]),      // a list and a calendar: neutral, time → event
            ("pay rent friday 10am #personal", [.task, .event]),
            ("remind me to call mom tomorrow 6pm", [.task, .event]),
            ("todo email Anna friday 9am", [.task, .event]),
            // 4. A day: with a time event first, alone task first.
            ("call mom tomorrow 6pm", [.event, .task]),
            ("call mom tomorrow", [.task, .event]),
            ("take vitamins every day", [.task, .event]),
            // 5. No day.
            ("buy milk", [.task]),
            ("lunch at Starbucks", [.task])
        ]
        for (text, kinds) in cases {
            let draft = await QuickAddParser().parse(text, lists: lists, calendars: calendars, referenceDate: reference, calendar: calendar)
            XCTAssertEqual(QuickAddKindDecision.decide(draft).kinds, kinds, text)
        }
    }

    /// The event a draft becomes: default hour, durations, all day, spans.
    func testEventDrafts() async {
        func event(_ text: String) async -> EventDraft {
            await parse(text).eventDraft(calendar: calendar, referenceDate: reference)
        }
        func at(_ d: Int, _ h: Int, _ m: Int = 0, month: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: h, minute: m))!
        }
        let lunch = await event("lunch tomorrow 1pm @Starbucks")
        XCTAssertEqual(lunch.title, "Lunch")
        XCTAssertEqual(lunch.location, "Starbucks")
        XCTAssertEqual([lunch.start, lunch.end], [at(24, 13), at(24, 14)], "no end: an hour")
        XCTAssertFalse(lunch.isAllDay)

        let call = await event("call with Anna tomorrow 3pm for 30 min")
        XCTAssertEqual([call.start, call.end], [at(24, 15), at(24, 15, 30)])

        let range = await event("standup tomorrow 10:00-10:15")
        XCTAssertEqual([range.start, range.end], [at(24, 10), at(24, 10, 15)])

        let late = await event("party friday 22-01")
        XCTAssertEqual([late.start, late.end], [at(25, 22), at(26, 1)], "past midnight ends the next day")

        let offsite = await event("offsite friday all day")
        XCTAssertTrue(offsite.isAllDay)
        XCTAssertEqual([offsite.start, offsite.end], [day(2026, 9, 25), day(2026, 9, 25)])

        let trip = await event("conference 3-5 oct")
        XCTAssertTrue(trip.isAllDay)
        XCTAssertEqual([trip.start, trip.end], [day(2026, 10, 3), day(2026, 10, 5)])

        let weekly = await event("gym every Monday 18-19 remind me 15m before")
        XCTAssertEqual(weekly.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(weekly.alerts, [.before(minutes: 15)])
        XCTAssertEqual([weekly.start, weekly.end], [at(28, 18), at(28, 19)])
    }

    /// "Daily" is a name when a later word repeats it; "starting" is glue.
    func testRepeatWordsAndStartingDays() async throws {
        let daily = await parse("daily starting next week tue 11-12 weekly")
        XCTAssertEqual(daily.title, "Daily")
        XCTAssertEqual(daily.recurrence?.frequency, .weekly)
        XCTAssertEqual(daily.day, day(2026, 9, 29))
        XCTAssertEqual(daily.startTime?.hour, 11)
        XCTAssertEqual(daily.endTime?.hour, 12)
        XCTAssertEqual(QuickAddKindDecision.decide(daily).kinds, [.event])

        let report = await parse("send weekly report daily")
        XCTAssertEqual(report.title, "Send weekly report")
        XCTAssertEqual(report.recurrence?.frequency, .daily)

        let every = await parse("something 11-12 starting next week tue every 2 days")
        XCTAssertEqual(every.title, "Something")
        XCTAssertEqual(every.recurrence?.interval, 2)
        XCTAssertEqual(every.day, day(2026, 9, 29))
        XCTAssertEqual(every.startTime?.hour, 11)

        let pages = await parse("read chapters 3-5 every day")
        XCTAssertEqual(pages.title, "Read chapters 3-5", "counted things stay text")
        XCTAssertNil(pages.startTime)
        let days = await parse("conference oct 3-5 weekly")
        XCTAssertNil(days.startTime, "days next to a month aren't hours")
    }

    /// Where: "@Office", "@\"Office, room 14\"", "at"/"in" + a place.
    func testLocations() async {
        let cases: [(String, String, String?)] = [
            ("standup tomorrow 10am @Office", "Standup", "Office"),
            ("standup tomorrow 10am @\"Office, room 14\"", "Standup", "Office, room 14"),
            ("standup tomorrow 10am @ \"Office, room 14\"", "Standup", "Office, room 14"),
            ("coffee with Anna at Starbucks tomorrow 9am", "Coffee with Anna", "Starbucks"),
            ("review friday 2pm in Room 4", "Review", "Room 4"),
            ("dinner at Bank of America Plaza friday 7pm", "Dinner", "Bank of America Plaza"),
            ("offsite friday at \"the old mill\"", "Offsite", "the old mill"),
            ("lunch tomorrow at 1pm", "Lunch", nil),         // a time, not a place
            ("call at 3", "Call", nil),
            ("plan trip in March", "Plan trip", nil),        // a month, not a place
            ("renew passport in 3 months", "Renew passport", nil),
            ("meet at noon tomorrow", "Meet", nil),
            ("standup tomorrow @10", "Standup", nil),        // "@10" is a time
            ("email anna@example.com tomorrow", "Email anna@example.com", nil)  // an email isn't a place
        ]
        for (text, title, place) in cases {
            let draft = await parse(text)
            XCTAssertEqual(draft.location, place, text)
            XCTAssertEqual(draft.eventTitle, title, text)
            if place == nil { XCTAssertEqual(draft.title, title, text) }
        }
        // A task has no place field: the place stays in its title.
        let parcel = await parse("pick up parcel at Post Office tomorrow")
        XCTAssertEqual(parcel.title, "Pick up parcel at Post Office")
        XCTAssertEqual(parcel.eventTitle, "Pick up parcel")
        let office = await parse("standup tomorrow 10am @Office")
        XCTAssertEqual(office.title, "Standup @Office")
    }

    /// "#name" names a list, a calendar, or both; "t:e" / "t:t" force a kind.
    func testCalendarTagsAndForcedKind() async {
        let calendars = [QuickAddList(id: "cal-work", title: "Work"), QuickAddList(id: "cal-family", title: "Family")]
        func parse(_ text: String) async -> QuickAddDraft {
            await QuickAddParser().parse(text, lists: lists, calendars: calendars, referenceDate: reference, calendar: calendar)
        }
        let both = await parse("planning friday 10am #work")
        XCTAssertEqual(both.listID, "work")
        XCTAssertEqual(both.calendarID, "cal-work")
        XCTAssertEqual(both.title, "Planning")
        let calendarOnly = await parse("dinner friday 7pm #family")
        XCTAssertNil(calendarOnly.listID)
        XCTAssertEqual(calendarOnly.calendarID, "cal-family")
        XCTAssertEqual(calendarOnly.eventTitle, "Dinner")
        XCTAssertEqual(calendarOnly.title, "Dinner #family", "a task can't go in a calendar: the tag stays")
        let neither = await parse("dinner friday #gym")
        XCTAssertEqual(neither.title, "Dinner #gym", "unknown tags stay in the title")

        for (text, kind) in [("lunch friday 1pm t:e", QuickAddKind.event), ("pay rent friday t:t", .task),
                             ("lunch friday type:event", .event), ("pay rent friday T:Task", .task)] {
            let draft = await parse(text)
            XCTAssertEqual(draft.forcedKind, kind, text)
            XCTAssertFalse(draft.title.lowercased().contains(":"), text)
        }
        let forced = await parse("t:t groceries")
        XCTAssertGreaterThanOrEqual(forced.confidence, TaskQuickAddStage.threshold, "t:t forces a task, as + does")
    }

    func testAOneWordRepeatThatLeavesNoTitleIsTheTitle() async throws {
        let draft = try await XCTUnwrapAsync(await stage("daily on 11 nov 11am"))
        XCTAssertEqual(draft.title, "Daily")
        XCTAssertNil(draft.recurrence)
        XCTAssertEqual(draft.day, day(2026, 11, 11))
        XCTAssertEqual(draft.startTime?.hour, 11)
        let repeating = try await XCTUnwrapAsync(await stage("water plants daily at 9am"))
        XCTAssertEqual(repeating.title, "Water plants")
        XCTAssertNotNil(repeating.recurrence, "with a title, it's still a repeat")
        let bare = await stage("daily")
        XCTAssertNil(bare, "no date or time: stays search")
    }

    func testPlusForcesATask() async throws {
        let draft = try await XCTUnwrapAsync(await stage("+ milk tomorrow"))
        XCTAssertEqual(draft.title, "Milk")
        XCTAssertEqual(draft.day, day(2026, 9, 24))
    }

    // MARK: - Order doesn't matter

    func testSameMeaningInAnyWordOrder() async {
        let expected = await parse("send invoice next week at 10 am")
        XCTAssertEqual(expected.title, "Send invoice")
        XCTAssertEqual(expected.day, day(2026, 9, 28))
        XCTAssertEqual(expected.startTime?.hour, 10)
        for text in ["next week send invoice at 10 am", "send invoice 10 am next week", "next week at 10 am send invoice"] {
            let draft = await parse(text)
            XCTAssertEqual(draft.title, expected.title, text)
            XCTAssertEqual(draft.day, expected.day, text)
            XCTAssertEqual(draft.startTime?.hour, expected.startTime?.hour, text)
        }
    }

    // MARK: - Explicit syntax

    func testRecurrenceAndAlertAreRecognizedAndRemoved() async {
        let rent = await parse("pay rent every month on the 1st")
        XCTAssertEqual(rent.title, "Pay rent")
        XCTAssertEqual(rent.recurrence, TaskRecurrenceRule(frequency: .monthly, daysOfMonth: [1]))
        XCTAssertEqual(rent.day, day(2026, 10, 1), "starts at the next 1st")

        let plants = await parse("water plants every Sunday")
        XCTAssertEqual(plants.title, "Water plants")
        XCTAssertEqual(plants.recurrence?.weekdays, [.init(weekday: 1)])
        XCTAssertEqual(plants.day, day(2026, 9, 27), "the coming Sunday, not a one-off date")

        let mum = await parse("call mum tomorrow remind 15m before")
        XCTAssertEqual(mum.title, "Call mum")
        XCTAssertEqual(mum.alert, .relative(minutesBefore: 15))
        XCTAssertEqual(mum.day, day(2026, 9, 24))

        let biweekly = await parse("team sync every 2 weeks")
        XCTAssertEqual(biweekly.recurrence, TaskRecurrenceRule(frequency: .weekly, interval: 2))
    }

    func testListsMatchCaseInsensitivelyAndUnknownOnesStayInTheTitle() async {
        let home = await parse("buy milk #HOME")
        XCTAssertEqual(home.listID, "home")
        let unknown = await parse("buy milk #groceries")
        XCTAssertNil(unknown.listID)
        XCTAssertEqual(unknown.title, "Buy milk #groceries")
    }

    func testPriorityPhrases() async {
        let phrase = await parse("renew passport high priority")
        let one = await parse("renew passport !")
        let three = await parse("renew passport !!!")
        XCTAssertEqual(phrase.priority, .high)
        XCTAssertEqual(phrase.title, "Renew passport")
        XCTAssertEqual(one.priority, .low)
        XCTAssertEqual(three.priority, .high)
    }

    // MARK: - Diagnostic table (prints; doesn't fail on mismatches)

    private struct Case {
        let text: String
        /// "title | yyyy-MM-dd | HH:mm | list | priority | repeat | alert" — "-" for none.
        let expected: String
    }

    private let diagnosticCases: [Case] = """
    buy milk tomorrow|Buy milk | 2026-09-24 | - | - | none | - | -
    call bank Friday at 14|Call bank | 2026-09-25 | 14:00 | - | none | - | -
    send invoice next Monday #work|Send invoice | 2026-09-28 | - | work | none | - | -
    submit report tomorrow !!|Submit report | 2026-09-24 | - | - | medium | - | -
    book dentist Oct 3|Book dentist | 2026-10-03 | - | - | none | - | -
    pay rent every month on the 1st|Pay rent | 2026-10-01 | - | - | none | monthly d1 | -
    water plants every Sunday|Water plants | 2026-09-27 | - | - | none | weekly 1 | -
    call mum tomorrow remind 15m before|Call mum | 2026-09-24 | - | - | none | - | 15m
    renew insurance in 3 months #personal|Renew insurance | 2026-12-23 | - | personal | none | - | -
    10 am next week send invoice|Send invoice | 2026-09-28 | 10:00 | - | none | - | -
    invoid next week on frida|Invoid | 2026-10-02 | - | - | none | - | -
    10am - 11am dentist with Adrien 10 sept|Dentist with Adrien | 2027-09-10 | 10:00–11:00 | - | none | - | -
    """.split(separator: "\n").map { line in
        let parts = line.split(separator: "|", maxSplits: 1)
        return Case(text: String(parts[0]), expected: String(parts[1]))
    }

    private func describe(_ draft: QuickAddDraft) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let hm = { (c: DateComponents) in String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) }
        let time = draft.startTime.map { start in [hm(start), draft.endTime.map(hm)].compactMap { $0 }.joined(separator: "–") } ?? "-"
        var repeatText: String
        switch draft.recurrence?.frequency {
        case .daily?: repeatText = "daily"
        case .weekly?: repeatText = "weekly"
        case .monthly?: repeatText = "monthly"
        case .yearly?: repeatText = "yearly"
        case nil: repeatText = "-"
        }
        if let rule = draft.recurrence {
            if rule.interval > 1 { repeatText += "×\(rule.interval)" }
            if !rule.weekdays.isEmpty { repeatText += " " + rule.weekdays.map { String($0.weekday) }.joined(separator: ",") }
            if !rule.daysOfMonth.isEmpty { repeatText += " d" + rule.daysOfMonth.map(String.init).joined(separator: ",") }
        }
        let alert: String
        switch draft.alert {
        case .relative(let minutes)?: alert = "\(minutes)m"
        case .absolute?: alert = "abs"
        case nil: alert = "-"
        }
        let priority = draft.priority == .none ? "none" : draft.priority.title.lowercased()
        let days = draft.day.map { start in
            [formatter.string(from: start), draft.endDay.map(formatter.string(from:))].compactMap { $0 }.joined(separator: "..")
        } ?? "-"
        let when = draft.isAllDay ? (time == "-" ? "all day" : time + " all day") : time
        return [draft.title, days, when, draft.listID ?? "-",
                priority, repeatText, alert].joined(separator: " | ")
    }

    func testQuickAddDiagnosticTable() async {
        var counts = ["OK": 0, "NOT TASK": 0, "WRONG": 0]
        print("\nQUICK ADD — reference 2026-09-23 12:00 (host local time)")
        print("Status   | Input                                        | Expected / Actual")
        for item in diagnosticCases {
            let draft = await parse(item.text)
            let actual = describe(draft)
            let isTask = draft.confidence >= TaskQuickAddStage.threshold
            let status = !isTask ? "NOT TASK" : (actual == item.expected ? "OK" : "WRONG")
            counts[status, default: 0] += 1
            print(String(format: "%-8s | %-44s | %@", (status as NSString).utf8String!, (item.text as NSString).utf8String!, item.expected))
            if status != "OK" {
                print(String(format: "%-8s | %-44s | %@  (confidence %.2f)", "", "", actual, draft.confidence))
            }
        }
        print("TOTAL: \(diagnosticCases.count)  OK: \(counts["OK"]!)  NOT TASK: \(counts["NOT TASK"]!)  WRONG: \(counts["WRONG"]!)\n")
        XCTAssertEqual(counts["OK"], diagnosticCases.count, "every diagnostic case parses exactly as expected (see the table above)")
    }

    // MARK: - User-supplied intent corpus (prints; doesn't fail)

    /// Each line: `[category] input`. Expected outcome per category:
    /// parse → a task; reject → not a task; ambiguous / wild → shown only.
    private let intentCorpus = """
    [parse] buy milk
    [parse] buy milk tomorrow
    [parse] call John tomorrow
    [parse] send invoice Friday
    [parse] book dentist next Monday
    [parse] pay electricity bill today
    [parse] finish report tonight
    [parse] water plants Saturday
    [parse] email Tom tomorrow
    [parse] renew insurance next month
    [parse] buy milk at 5 pm
    [parse] call John at 10 am
    [parse] send invoice tomorrow at 11
    [parse] book dentist Friday at 14:30
    [parse] pay rent on October 1
    [parse] submit report Sep 30 at 9
    [parse] pick up parcel in 2 hours
    [parse] call mum in 30 minutes
    [parse] renew passport in 3 months
    [parse] check backups in a week
    [parse] buy milk #groceries
    [parse] send invoice #work
    [parse] call mum #personal
    [parse] finish report tomorrow #work
    [parse] buy milk tomorrow #groceries
    [parse] book dentist Friday #personal
    [parse] submit report at 10 #work
    [parse] pay rent Oct 1 #home
    [parse] renew insurance next month #personal
    [parse] order coffee beans Saturday #home
    [parse] send invoice !
    [parse] send invoice !!
    [parse] send invoice !!!
    [parse] send invoice tomorrow !!
    [parse] finish report Friday #work !!
    [parse] book flights next week !
    [parse] call bank tomorrow high priority
    [parse] renew certificate Friday important
    [parse] submit proposal Monday low priority
    [parse] pay invoice tomorrow medium priority
    [parse] every day take vitamins
    [parse] take vitamins every day
    [parse] water plants every Sunday
    [parse] every Monday send status report
    [parse] send status report every Monday
    [parse] review budget weekly
    [parse] pay rent monthly
    [parse] renew domain yearly
    [parse] check backups every 2 weeks
    [parse] water flowers every 3 days
    [parse] send invoice every month on the 1st
    [parse] pay credit card every month on the 15th
    [parse] take medication every weekday
    [parse] run backup every Friday at 22:00
    [parse] call parents every Sunday at 18
    [parse] review goals every month on the last day
    [parse] submit timesheet every second Friday
    [ambiguous] clean fridge every other week
    [parse] review portfolio quarterly
    [ambiguous] change filter every six months
    [parse] call John tomorrow remind 15m before
    [parse] send invoice Friday remind 1h before
    [parse] dentist Monday at 10 alert 30 minutes before
    [parse] pay rent Oct 1 remind at due time
    [parse] submit report tomorrow remind me 10m before
    [parse] call mum at 18 reminder 5 minutes before
    [parse] flight check-in Friday at 12 remind 2h before
    [parse] take medication daily remind at due time
    [parse] water plants Sunday alert 1 hour before
    [parse] renew certificate next month remind 1 day before
    [parse] 10 am tomorrow send invoice
    [parse] 10 am Friday call John
    [parse] 10 am next week send invoice
    [parse] tomorrow at 10 send invoice
    [parse] next Friday at 2 pm call the bank
    [parse] Friday call the bank at 2 pm
    [parse] at 2 pm Friday call the bank
    [parse] call the bank 2 pm Friday
    [parse] #work tomorrow 10am send invoice
    [parse] !! next Monday finish architecture document #work
    [parse] tomorrow send invoice #work !!
    [parse] #work send invoice tomorrow !!
    [parse] !! send invoice #work tomorrow
    [parse] tomorrow !! #work send invoice
    [parse] send invoice !! tomorrow #work
    [parse] every Friday #work send weekly report
    [parse] #work every Friday send weekly report
    [parse] send weekly report #work every Friday
    [parse] at 17 every Friday send weekly report #work
    [parse] every Friday at 17 send weekly report #work !!
    [parse] send invoice next week at 10
    [parse] next week send invoice at 10
    [parse] at 10 next week send invoice
    [parse] next week at 10 send invoice
    [parse] send invoice at 10 next week
    [parse] #work 10 am next week send invoice !!
    [parse] !! 10am #work next week send invoice
    [parse] next week #work send invoice 10am !!
    [parse] send invoice !! #work at 10 next week
    [parse] at 10 !! send invoice next week #work
    [parse] buy milk tomorrow morning
    [parse] call bank tomorrow afternoon
    [parse] send report tomorrow evening
    [ambiguous] finish slides tonight
    [parse] take medication at noon
    [parse] call John at midnight
    [parse] run backup at 00:30
    [parse] send report at 23:59
    [ambiguous] call John around 10
    [ambiguous] dentist sometime Friday morning
    [parse] send report before Friday
    [ambiguous] send report by Friday
    [ambiguous] finish this by end of week
    [parse] submit report end of next week
    [ambiguous] pay invoice early next week
    [ambiguous] call supplier late afternoon
    [ambiguous] book hotel sometime next month
    [ambiguous] review contract after lunch tomorrow
    [ambiguous] call John before dinner
    [ambiguous] buy milk on the way home
    [parse] call May tomorrow
    [ambiguous] call May 10
    [parse] meet May next Friday
    [ambiguous] May send invoice
    [parse] send May the invoice tomorrow
    [parse] march report due tomorrow
    [ambiguous] March invoice
    [parse] review June numbers Friday
    [ambiguous] June 5 report
    [parse] call April tomorrow at 10
    [parse] work on presentation tomorrow
    [parse] work on presentation tomorrow #work
    [ambiguous] work tomorrow
    [reject] work
    [parse] home insurance renewal Friday
    [reject] home
    [parse] personal tax return next month
    [reject] personal
    [parse] groceries tomorrow
    [ambiguous] groceries
    [parse] invoice 10 tomorrow
    [ambiguous] invoice 10
    [parse] buy 10 apples tomorrow
    [parse] order 20 cables Friday
    [parse] pay invoice 12345 tomorrow
    [parse] call room 101 tomorrow at 10
    [parse] version 10 release checklist Friday
    [parse] review issue 123 at 14:00
    [ambiguous] 10 invoice tomorrow
    [parse] 10am invoice tomorrow
    [parse] send invoice on 10/11
    [ambiguous] send invoice 10/11
    [ambiguous] call John 3/4
    [parse] submit VAT return 30.09
    [parse] submit VAT return 30/09/2026
    [parse] call John 2026-10-03 at 14:00
    [ambiguous] book hotel 04/05
    [parse] book hotel May 4
    [parse] book hotel 4 May
    [parse] book hotel May 4th
    [parse] send invoice tomorrow, 10 am, #work, !!
    [parse] send invoice — tomorrow at 10 — #work
    [parse] send invoice; Friday; 14:00; #work
    [parse] #work: send invoice tomorrow at 10
    [parse] tomorrow @ 10:00 — send invoice #work
    [parse] send invoice (tomorrow at 10)
    [parse] send invoice [tomorrow 10am] #work
    [parse] SEND INVOICE TOMORROW AT 10
    [parse] send    invoice    tomorrow    at    10
    [parse] send invoice tomorrow@10
    [parse] send invoice tmrw at 10
    [parse] send invoice tom at 10
    [parse] send invoice nxt fri 10am
    [parse] send invoice next fri 10
    [ambiguous] invoice fri 10
    [parse] + send invoice tomorrow at 10
    [parse] + tomorrow at 10 send invoice
    [parse] + #work !! send invoice tomorrow
    [parse] + every Friday 17 send status report #work
    [parse] + call mum tomorrow remind 15m before
    [reject] tomorrow
    [reject] next week
    [reject] next Friday
    [reject] 10 am
    [reject] Friday 10 am
    [reject] October
    [reject] October 10
    [reject] this month
    [reject] end of next week
    [reject] three days from now
    [ambiguous] invoice tomorrow
    [ambiguous] John Friday
    [ambiguous] dentist 10
    [ambiguous] meeting with Tom Friday at 10
    [ambiguous] lunch with Tom Friday 12-13
    [ambiguous] flight to London Friday 18:30
    [ambiguous] gym every Monday 18-19
    [ambiguous] birthday John May 5
    [ambiguous] vacation next week
    [wild] !! #work next Friday at 10am remind me 45m before and then every second Friday send the damn invoice to John about project May 10
    """

    func testQuickAddIntentCorpus() async {
        var tally: [String: (expected: Int, met: Int)] = [:]
        var snapshot: [String] = []
        print("\nQUICK ADD INTENT CORPUS — reference 2026-09-23 12:00 (host local time)")
        print("✓ = as expected, ✗ = not as expected, · = no expectation (ambiguous / wild)")
        print("  | category  | verdict  | conf | input")
        print("  |           |          |      |   → title | date | time | list | priority | repeat | alert")
        for line in intentCorpus.split(separator: "\n") {
            guard let close = line.firstIndex(of: "]") else { continue }
            let category = String(line[line.index(after: line.startIndex)..<close])
            let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            let draft = await parse(text)
            let isTask = draft.confidence >= TaskQuickAddStage.threshold
            snapshot.append("[\(category)] \(text) → \(isTask ? "TASK" : "NOT TASK") · \(describe(draft))")
            if category == "parse" { XCTAssertTrue(isTask, "should be a task: \(text)") }
            if category == "reject" { XCTAssertFalse(isTask, "must not be a task: \(text)") }
            let mark: String
            switch category {
            case "parse": mark = isTask ? "✓" : "✗"
            case "reject": mark = isTask ? "✗" : "✓"
            default: mark = "·"
            }
            var entry = tally[category] ?? (0, 0)
            entry.expected += 1
            if mark == "✓" { entry.met += 1 }
            tally[category] = entry
            print(String(format: "%@ | %-9s | %-8s | %.2f | %@", mark, (category as NSString).utf8String!,
                         ((isTask ? "TASK" : "NOT TASK") as NSString).utf8String!, draft.confidence, text))
            print("  |           |          |      |   → \(describe(draft))")
        }
        let summary = tally.keys.sorted().map { key in
            let entry = tally[key]!
            return key == "parse" || key == "reject" ? "\(key): \(entry.met)/\(entry.expected) as expected" : "\(key): \(entry.expected) shown"
        }
        print("SUMMARY — " + summary.joined(separator: " · ") + "\n")
        // Everything parsed — title, day, time, list, priority, repeat,
        // alert — not just the verdict, so a parser change can't quietly
        // move a date.
        GoldenSnapshot.assertMatches(snapshot, named: "quick-add-corpus")
    }

}

/// `XCTUnwrap` for an already-awaited optional, with a readable message.
private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, "expected a task draft", file: file, line: line)
}
