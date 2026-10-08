import XCTest
@testable import Shell
@testable import Domain

final class TaskRecurrenceRuleTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Days in [from, to] the rule lands on, starting from `start`.
    private func occurrences(_ rule: TaskRecurrenceRule, start: Date, from: Date, to: Date) -> [Date] {
        var result: [Date] = []
        var current = from
        while current <= to {
            if rule.occurs(on: current, startingAt: start, calendar: calendar) { result.append(current) }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    /// Exactly what Reminders.app stores for "Monthly" on the 30th: the last
    /// of the 28th/29th/30th, so short months still get one.
    func testRemindersMonthlyOnThe30th() {
        let rule = TaskRecurrenceRule(frequency: .monthly, daysOfMonth: [28, 29, 30], setPositions: [-1])
        let start = day(2026, 9, 30)
        XCTAssertEqual(occurrences(rule, start: start, from: day(2026, 10, 1), to: day(2027, 3, 31)), [
            day(2026, 10, 30), day(2026, 11, 30), day(2026, 12, 30),
            day(2027, 1, 30), day(2027, 2, 28), day(2027, 3, 30)
        ])
    }

    func testEveryThreeMonths() {
        let rule = TaskRecurrenceRule(frequency: .monthly, interval: 3)
        XCTAssertEqual(occurrences(rule, start: day(2026, 9, 15), from: day(2026, 9, 16), to: day(2027, 4, 30)),
                       [day(2026, 12, 15), day(2027, 3, 15)])
    }

    func testSimpleMonthlySkipsMonthsWithoutTheDay() {
        let rule = TaskRecurrenceRule(frequency: .monthly)
        XCTAssertEqual(occurrences(rule, start: day(2026, 8, 31), from: day(2026, 9, 1), to: day(2026, 12, 31)),
                       [day(2026, 10, 31), day(2026, 12, 31)])
    }

    func testSecondTuesdayAndLastWeekdayOfTheMonth() {
        let secondTuesday = TaskRecurrenceRule(frequency: .monthly, weekdays: [.init(weekday: 3, ordinal: 2)])
        XCTAssertEqual(occurrences(secondTuesday, start: day(2026, 9, 8), from: day(2026, 9, 9), to: day(2026, 11, 30)),
                       [day(2026, 10, 13), day(2026, 11, 10)])

        let lastWeekday = TaskRecurrenceRule(frequency: .monthly, weekdays: (2...6).map { .init(weekday: $0) }, setPositions: [-1])
        XCTAssertEqual(occurrences(lastWeekday, start: day(2026, 9, 30), from: day(2026, 10, 1), to: day(2026, 11, 30)),
                       [day(2026, 10, 30), day(2026, 11, 30)])
    }

    func testWeeklyOnSeveralDaysEveryOtherWeek() {
        let rule = TaskRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [.init(weekday: 2), .init(weekday: 4)])
        // Starts Monday 28 Sep: that week, skip next, then the week after.
        XCTAssertEqual(occurrences(rule, start: day(2026, 9, 28), from: day(2026, 9, 29), to: day(2026, 10, 18)),
                       [day(2026, 9, 30), day(2026, 10, 12), day(2026, 10, 14)])
    }

    func testDailyYearlyAndEnds() {
        XCTAssertEqual(occurrences(TaskRecurrenceRule(frequency: .daily, interval: 3), start: day(2026, 9, 1),
                                   from: day(2026, 9, 2), to: day(2026, 9, 10)),
                       [day(2026, 9, 4), day(2026, 9, 7), day(2026, 9, 10)])
        XCTAssertEqual(occurrences(TaskRecurrenceRule(frequency: .yearly), start: day(2024, 2, 29),
                                   from: day(2024, 3, 1), to: day(2028, 12, 31)),
                       [day(2028, 2, 29)])

        let until = TaskRecurrenceRule(frequency: .daily, endDate: day(2026, 9, 3))
        XCTAssertEqual(occurrences(until, start: day(2026, 9, 1), from: day(2026, 9, 2), to: day(2026, 9, 10)),
                       [day(2026, 9, 2), day(2026, 9, 3)])
        let count = TaskRecurrenceRule(frequency: .weekly, occurrenceCount: 3)
        XCTAssertEqual(occurrences(count, start: day(2026, 9, 1), from: day(2026, 9, 2), to: day(2026, 12, 31)),
                       [day(2026, 9, 8), day(2026, 9, 15)], "3 occurrences including the first")
    }

    func testNeverBeforeTheStartAndUnsupportedPartsAreNotGuessed() {
        let rule = TaskRecurrenceRule(frequency: .daily)
        XCTAssertFalse(rule.occurs(on: day(2026, 8, 31), startingAt: day(2026, 9, 1), calendar: calendar))
        var odd = TaskRecurrenceRule(frequency: .yearly)
        odd.hasUnsupportedParts = true
        XCTAssertFalse(odd.occurs(on: day(2027, 9, 1), startingAt: day(2026, 9, 1), calendar: calendar))
    }

    func testStandardMenuValuesBuildTheSameRules() {
        XCTAssertNil(TaskRecurrenceRule(standard: .never))
        XCTAssertNil(TaskRecurrenceRule(standard: .custom("x")))
        XCTAssertEqual(TaskRecurrenceRule(standard: .biweekly), TaskRecurrenceRule(frequency: .weekly, interval: 2))
        XCTAssertEqual(TaskRecurrenceRule(standard: .weekdays)?.weekdays.map(\.weekday), [2, 3, 4, 5, 6])
    }

    /// The real bug: a Reminders monthly task must show on later months.
    func testIndexProjectsTheRemindersMonthlyRule() {
        let task = TaskItem(id: "faktura", title: "Faktura", listID: "l", dueDate: day(2026, 9, 30).addingTimeInterval(36_000),
                            hasDueTime: true, recurrence: .monthly,
                            recurrenceRule: TaskRecurrenceRule(frequency: .monthly, daysOfMonth: [28, 29, 30], setPositions: [-1]))
        let index = ScheduledTaskIndex(tasks: [task], now: day(2026, 9, 26), calendar: calendar, signature: 1)
        for target in [day(2026, 11, 30), day(2026, 12, 30), day(2027, 2, 28)] {
            XCTAssertEqual(index.tasks(on: target, calendar: calendar).timed.map(\.id), ["faktura"], "\(target)")
        }
        XCTAssertEqual(index.tasks(on: day(2026, 11, 30), calendar: calendar).timed.first?.dueDate,
                       day(2026, 11, 30).addingTimeInterval(36_000), "keeps 10:00")
    }
}
