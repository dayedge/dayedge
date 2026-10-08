import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// When entries were created and last changed, as the tools report it.
/// Reference: Wednesday 23 September 2026 12:00 UTC.
final class AssistantFreshnessTests: XCTestCase {
    private typealias T = AssistantTestData

    func testEventDetailsSayWhenItWasCreatedAndChanged() async throws {
        let context = T.context(events: [24: [
            T.event("Review", day: 24, from: (14, 0), to: (15, 0), created: T.date(21, 9, 5), modified: T.date(22, 16, 30)),
            T.event("Daily", day: 24, from: (10, 30), to: (10, 55), created: T.date(1, 8, month: 3), recurring: true)
        ]])
        let review = try await EventDetailsTool.make(context).call(AssistantToolArguments(["event": .string("review")]))
        XCTAssertTrue(review.contains("\nCreated 21 Sep 2026 09:05 · Last changed 22 Sep 2026 16:30\n"), review)

        let daily = try await EventDetailsTool.make(context).call(AssistantToolArguments(["event": .string("daily")]))
        XCTAssertTrue(daily.contains("\nCreated 1 Mar 2026 08:00 (the whole series)\n"), daily)
    }

    func testRecentlyAddedTasksNewestFirstWithTheirDates() async throws {
        let context = T.context(tasks: [
            TaskItem(id: "old", title: "Old chore", listID: "home", creationDate: T.date(1, month: 8)),
            TaskItem(id: "a", title: "Buy tickets", listID: "home", creationDate: T.date(20, 18)),
            TaskItem(id: "b", title: "Send invoice", listID: "work", creationDate: T.date(22, 9))
        ])
        let answer = try await TaskListTool.make(context).call(AssistantToolArguments(["filter": .string("recent")]))
        XCTAssertEqual(answer, """
        Recent tasks in all lists (2):
        [[T1]] task Send invoice · Work · added 22 Sep 2026
        [[T2]] task Buy tickets · Home · added 20 Sep 2026
        \(AssistantFormat.referenceHint)
        """)
    }

    func testNewestEventsFirstWithOneLinePerSeriesAndNoTextNeeded() async throws {
        let context = T.context(events: [
            24: [T.event("Daily", day: 24, from: (10, 30), to: (10, 55), created: T.date(1, month: 3), recurring: true),
                 T.event("Offsite", day: 24, created: T.date(22))],
            25: [T.event("Daily", day: 25, from: (10, 30), to: (10, 55), created: T.date(1, month: 3), recurring: true),
                 T.event("Dentist", day: 25, from: (8, 0), to: (9, 0), created: T.date(18))]
        ])
        let answer = try await EventSearchTool.make(context).call(AssistantToolArguments(["order": .string("newest")]))
        let lines = answer.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "Events in Wednesday 23 September 2026 – Thursday 22 October 2026, most recently added first:")
        XCTAssertEqual(Array(lines.dropFirst().prefix(3)), [
            "[[E1]] event Thu 24 Sep all day Offsite · Work · added 22 Sep 2026",
            "[[E2]] event Fri 25 Sep 08:00–09:00 Dentist · Work · added 18 Sep 2026",
            "[[E3]] event Thu 24 Sep 10:30–10:55 Daily · Work · added 1 Mar 2026"
        ], "the daily series appears once")
    }
}
