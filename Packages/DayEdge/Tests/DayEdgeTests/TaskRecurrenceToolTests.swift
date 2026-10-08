import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// `task_recurrence` and the rule's past/future projection. Reference:
/// Wednesday 23 September 2026 12:00 UTC.
final class TaskRecurrenceToolTests: XCTestCase {
    private typealias T = AssistantTestData
    private let monthlyOn15th = TaskRecurrenceRule(frequency: .monthly, daysOfMonth: [15])

    private var invoice: TaskItem {
        TaskItem(id: "invoice", title: "Send invoice", listID: "work", dueDate: T.date(15, 10, month: 10), hasDueTime: true,
                 recurrence: .monthly, recurrenceRule: monthlyOn15th, creationDate: T.date(3, month: 8))
    }

    private func run(_ context: AssistantToolContext, _ arguments: [String: JSONValue]) async throws -> String {
        try await TaskRecurrenceTool.make(context).call(AssistantToolArguments(arguments))
    }

    // MARK: - The rule, past and future

    func testDatesBeforeTheCurrentOneFollowThePatternButNotBeforeCreation() {
        let range = DateInterval(start: T.date(1, month: 7), end: T.date(1, month: 12))
        let dates = monthlyOn15th.occurrences(in: range, anchoredAt: T.date(15, month: 10), notBefore: T.date(3, month: 8), calendar: T.calendar)
        XCTAssertEqual(dates, [T.date(15, month: 8), T.date(15, month: 9), T.date(15, month: 10), T.date(15, month: 11)])
    }

    func testTheEndAndCountApplyGoingForward() {
        let weekly = TaskRecurrenceRule(frequency: .weekly, occurrenceCount: 3)
        let range = DateInterval(start: T.date(1, month: 10), end: T.date(1, month: 11))
        XCTAssertEqual(weekly.occurrences(in: range, anchoredAt: T.date(2, month: 10), notBefore: nil, calendar: T.calendar),
                       [T.date(2, month: 10), T.date(9, month: 10), T.date(16, month: 10)])

        let ending = TaskRecurrenceRule(frequency: .weekly, endDate: T.date(10, month: 10))
        XCTAssertEqual(ending.occurrences(in: range, anchoredAt: T.date(2, month: 10), notBefore: nil, calendar: T.calendar),
                       [T.date(2, month: 10), T.date(9, month: 10)])
    }

    // MARK: - The tool

    func testDescribesTheRuleAndMarksPastNextAndUpcomingDates() async throws {
        let context = T.context(tasks: [invoice])
        let answer = try await run(context, ["task": .string("send invoice")])
        XCTAssertEqual(answer, """
        [[T1]] task Send invoice · due Thu 15 Oct 10:00 · Work · repeats
        Repeats: Every month on the 15th. No end date.
        Created Monday 3 August 2026.
        Dates in Wednesday 26 August 2026 – Wednesday 18 November 2026:
        - Tue 15 Sep 10:00 · past
        - Thu 15 Oct 10:00 · next due
        - Sun 15 Nov 10:00
        Past dates follow the rule; Reminders doesn't record which of them were completed.
        \(AssistantFormat.referenceHint)
        """)
    }

    func testARequestedPeriodAndAReferenceWork() async throws {
        let context = T.context(tasks: [invoice])
        _ = try await run(context, ["task": .string("Send invoice")]) // mints T1
        let answer = try await run(context, ["task": .string("[[T1]]"), "when": .string("2026-07-01..2026-12-31")])
        let dates = answer.split(separator: "\n").filter { $0.hasPrefix("- ") }.map { String($0.prefix(12)) }
        XCTAssertEqual(dates, ["- Sat 15 Aug", "- Tue 15 Sep", "- Thu 15 Oct", "- Sun 15 Nov", "- Tue 15 Dec"],
                       "nothing before the task was created (3 Aug)")
    }

    func testNonRepeatingAmbiguousAndMissingTasksAreExplained() async throws {
        let context = T.context(tasks: [
            invoice,
            TaskItem(id: "a", title: "Call Anna", listID: "home"),
            TaskItem(id: "b", title: "Call Bob", listID: "home")
        ])
        let single = try await run(context, ["task": .string("call anna")])
        XCTAssertTrue(single.hasSuffix("“Call Anna” doesn't repeat."), single)

        let several = try await run(context, ["task": .string("call")])
        XCTAssertTrue(several.hasPrefix("Several tasks match “call”; which one?"), several)
        XCTAssertTrue(several.contains("Call Anna") && several.contains("Call Bob"), several)

        let missing = try await run(context, ["task": .string("groceries")])
        XCTAssertEqual(missing, "No task matching “groceries”.")
    }

    func testListTasksCanFindTheRepeatingOnes() async throws {
        let context = T.context(tasks: [invoice, TaskItem(id: "a", title: "Call Anna", listID: "home")])
        let answer = try await TaskListTool.make(context).call(AssistantToolArguments(["filter": .string("repeating")]))
        XCTAssertTrue(answer.hasPrefix("Repeating tasks in all lists (1):\n[[T1]] task Send invoice"), answer)
    }
}
