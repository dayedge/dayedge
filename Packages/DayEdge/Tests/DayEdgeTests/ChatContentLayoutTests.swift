import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// Date context around referenced objects. Reference: Wednesday
/// 23 September 2026 12:00 UTC.
final class ChatContentLayoutTests: XCTestCase {
    private typealias T = AssistantTestData

    private func event(_ id: String, day: Int) -> ChatContentPart {
        .event(ChatEventReference(id: id, day: T.date(day), snapshot: .init(title: id)))
    }

    private func task(_ id: String, day: Int) -> ChatContentPart {
        .task(ChatTaskReference(id: id, day: T.date(day), snapshot: .init(title: id)))
    }

    private func day(_ number: Int, label: String? = nil, holiday: Bool = false) -> ChatDayReference {
        ChatDayReference(day: T.date(number), label: label, isHoliday: holiday)
    }

    func testEventsAndTasksGroupByDayAndProseSplitsGroups() {
        let parts: [ChatContentPart] = [
            .text("The notes differ:"),
            task("faktura", day: 24), event("daily", day: 24), event("sdlc", day: 24),
            event("planning", day: 25),
            .text("And later:"),
            event("review", day: 25)
        ]
        XCTAssertEqual(ChatContentBlock.blocks(parts, calendar: T.calendar), [
            .prose("The notes differ:"),
            .objects(day(24), [task("faktura", day: 24), event("daily", day: 24), event("sdlc", day: 24)]),
            .objects(day(25), [event("planning", day: 25)]),
            .prose("And later:"),
            .objects(day(25), [event("review", day: 25)])
        ], "a new day or prose starts a new group, and every group gets its date")
    }

    func testDaysFormOneRunAndALoneDayBecomesItsObjectsHeading() {
        let christmas = [day(24, label: "Wigilia", holiday: true), day(25, label: "Boże Narodzenie", holiday: true), day(26), day(27)]
        XCTAssertEqual(ChatContentBlock.blocks([.text("Święta:")] + christmas.map(ChatContentPart.day) + [.text("Cztery dni wolne.")],
                                               calendar: T.calendar),
                       [.prose("Święta:"), .dates(christmas), .prose("Cztery dni wolne.")])

        let heading = day(24, label: "Wigilia", holiday: true)
        XCTAssertEqual(ChatContentBlock.blocks([.day(heading), event("daily", day: 24)], calendar: T.calendar),
                       [.objects(heading, [event("daily", day: 24)])], "the date isn't shown twice, and keeps its name")
        XCTAssertEqual(ChatContentBlock.blocks([.day(day(23)), event("daily", day: 24)], calendar: T.calendar).count, 2,
                       "a different day stays its own date")
    }

    func testThePresentationIsChosenByCountNotByTheModel() {
        XCTAssertEqual(ChatDatePresentation.choose(count: 1), .single)
        XCTAssertEqual(ChatDatePresentation.choose(count: 2), .strip)
        XCTAssertEqual(ChatDatePresentation.choose(count: 7), .strip)
        XCTAssertEqual(ChatDatePresentation.choose(count: 8), .byMonth)
    }

    func testWeekendsOutrankHolidaysAsInTheMonthGrid() {
        XCTAssertEqual(ChatDayReference(day: T.date(26), isHoliday: true, isWeekend: true).tint, .weekend)
        XCTAssertEqual(ChatDayReference(day: T.date(25), isHoliday: true).tint, .holiday)
        XCTAssertEqual(ChatDayReference(day: T.date(24)).tint, .plain)
    }

    func testDateWordsAreEnglishInTheRegionsOrder() {
        let dates = DatePresentationFormatter(regionalLocale: Locale(identifier: "pl_PL"))
        let christmas = T.calendar.date(from: DateComponents(year: 2026, month: 12, day: 25))!
        XCTAssertEqual(ChatDayText.dayNumber(christmas, calendar: T.calendar, dates: dates), "25")
        XCTAssertEqual(ChatDayText.weekday(christmas, calendar: T.calendar, dates: dates), "Fri")
        XCTAssertEqual(ChatDayText.month(christmas, calendar: T.calendar, dates: dates), "Dec", "English names in a Polish region")
        XCTAssertEqual(ChatDayText.weekdayAndMonth(christmas, now: T.now, calendar: T.calendar, dates: dates), "Fri Dec")
        XCTAssertEqual(ChatDayText.monthTitle(christmas, now: T.now, calendar: T.calendar, dates: dates), "December")
        let nextYear = T.calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        XCTAssertEqual(ChatDayText.monthTitle(nextYear, now: T.now, calendar: T.calendar, dates: dates), "January 2027")
        XCTAssertEqual(ChatDayText.spoken(ChatDayReference(day: christmas, label: "Christmas Day", isHoliday: true),
                                          calendar: T.calendar, dates: dates), "Friday 25 December 2026, Christmas Day")
    }

    func testLabelsAreRelativeNearTodayAndAlwaysConcrete() {
        let dates = DatePresentationFormatter(regionalLocale: Locale(identifier: "en_GB"))
        func label(_ date: Date) -> String { ChatDayLabel.text(for: date, now: T.now, calendar: T.calendar, dates: dates) }
        XCTAssertEqual(label(T.date(23)), "Today · Wed 23 Sep")
        XCTAssertEqual(label(T.date(24)), "Tomorrow · Thu 24 Sep")
        XCTAssertEqual(label(T.date(22)), "Yesterday · Tue 22 Sep")
        XCTAssertEqual(label(T.date(2, month: 10)), "Fri 2 Oct")
        let nextYear = T.calendar.date(from: DateComponents(year: 2027, month: 10, day: 12))!
        XCTAssertEqual(label(nextYear), "Tue 12 Oct 2027", "the year only outside the current one")
    }
}
