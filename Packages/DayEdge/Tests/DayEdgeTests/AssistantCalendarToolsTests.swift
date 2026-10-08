import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// The Tier 1 read-only tools, against fixed data. Reference: Wednesday
/// 23 September 2026 12:00 UTC.
final class AssistantCalendarToolsTests: XCTestCase {
    private typealias T = AssistantTestData
    private var calendar: Calendar { T.calendar }

    private func run(_ tool: AssistantTool, _ arguments: [String: JSONValue] = [:]) async throws -> String {
        try await tool.call(AssistantToolArguments(arguments))
    }

    // MARK: - Dates the model may pass

    func testKeywordsAndISODatesResolveExactly() {
        func interval(_ text: String) -> DateInterval? { AssistantWhen.exact(text, now: T.now, calendar: calendar) }
        XCTAssertEqual(interval("today"), DateInterval(start: T.date(23), end: T.date(24)))
        XCTAssertEqual(interval(" Tomorrow "), DateInterval(start: T.date(24), end: T.date(25)))
        XCTAssertEqual(interval("next week"), DateInterval(start: T.date(28), end: T.date(5, month: 10)), "Monday-first")
        XCTAssertEqual(interval("next 7 days"), DateInterval(start: T.date(23), end: T.date(30)))
        XCTAssertEqual(interval("2026-10-02"), DateInterval(start: T.date(2, month: 10), end: T.date(3, month: 10)))
        XCTAssertEqual(interval("2026-09-28..2026-09-30"), DateInterval(start: T.date(28), end: T.date(1, month: 10)))
        XCTAssertNil(interval("next friday"), "phrases go to the parser")
        XCTAssertNil(interval("2026-09-30..2026-09-28"), "a backwards range isn't a range")
    }

    func testPhrasesGoToTheDateParserAndNonsenseIsExplained() async throws {
        let context = T.context()
        let friday = try await AssistantWhen.resolve("next friday", context: context)
        XCTAssertEqual(friday, DateInterval(start: T.date(25), end: T.date(26)))

        let answer = try await run(AgendaTool.make(context), ["when": .string("whenever")])
        XCTAssertTrue(answer.hasPrefix("Couldn't read the date “whenever”. Use today, tomorrow"), answer)
    }

    // MARK: - get_agenda

    func testAgendaListsEventsAndTasksPerDay() async throws {
        let context = T.context(
            events: [24: [
                T.event("Standup", day: 24, from: (9, 0), to: (9, 30), place: "Room 4"),
                T.event("Offsite", day: 24, calendarName: "Home")
            ]],
            tasks: [
                TaskItem(id: "1", title: "Send invoice", listID: "work", dueDate: T.date(24, 10), hasDueTime: true, priority: .high),
                TaskItem(id: "2", title: "Water plants", listID: "home", dueDate: T.date(24))
            ]
        )
        let answer = try await run(AgendaTool.make(context), ["when": .string("tomorrow")])
        XCTAssertEqual(answer, """
        Agenda for Thursday 24 September 2026:
        [[D1]] Thursday 24 September 2026
        [[E1]] event 09:00–09:30 Standup · Work · Room 4
        [[E2]] event all day Offsite · Home
        [[T1]] task Water plants · Home
        [[T2]] task Send invoice · due 10:00 · Work · high priority
        \(AssistantFormat.referenceHint)
        """)
    }

    func testTodayCarriesOverdueTasksAndEmptyPeriodsSaySo() async throws {
        let context = T.context(tasks: [
            TaskItem(id: "1", title: "Renew passport", listID: "home", dueDate: T.date(20)),
            TaskItem(id: "2", title: "Done already", listID: "home", dueDate: T.date(20), isCompleted: true)
        ])
        let today = try await run(AgendaTool.make(context))
        XCTAssertEqual(today, """
        Agenda for Wednesday 23 September 2026:
        [[D1]] Wednesday 23 September 2026
        [[T1]] task Renew passport · due Sun 20 Sep · overdue · Home
        \(AssistantFormat.referenceHint)
        """)

        let empty = try await run(AgendaTool.make(context), ["when": .string("2026-10-02")])
        XCTAssertEqual(empty, "Nothing scheduled for Friday 2 October 2026.")
    }

    // MARK: - find_free_time

    func testFreeTimeIsBetweenTimedEventsFromNowToTheEndOfTheWorkday() async throws {
        let context = T.context(events: [23: [
            T.event("Lunch", day: 23, from: (13, 0), to: (14, 0)),
            T.event("Call", day: 23, from: (15, 0), to: (15, 15)),
            T.event("Cancelled", day: 23, from: (16, 0), to: (17, 0), status: .cancelled),
            T.event("Conference", day: 23)
        ]])
        let answer = try await run(FreeTimeTool.make(context))
        XCTAssertEqual(answer, """
        Free time (09:00–17:00 working hours, at least 30 min):
        [[D1]] Wednesday 23 September 2026: 12:00–13:00, 14:00–15:00, 15:15–17:00
        """)

        let long = try await run(FreeTimeTool.make(context), ["minutes": .number(90)])
        XCTAssertTrue(long.hasSuffix("Wednesday 23 September 2026: 15:15–17:00"), long)
    }

    func testFreeTimeOverSeveralDaysSkipsWeekendsAndPastDays() async throws {
        let answer = try await run(FreeTimeTool.make(T.context()), ["when": .string("this week")])
        let days = answer.split(separator: "\n").dropFirst().map { $0.components(separatedBy: ":").first! }
        XCTAssertEqual(days, ["[[D1]] Wednesday 23 September 2026", "[[D2]] Thursday 24 September 2026", "[[D3]] Friday 25 September 2026"])
    }

    func testGapsHandleOverlapsAndMinimums() {
        let window = DateInterval(start: T.date(23, 9), end: T.date(23, 17))
        let busy = [
            DateInterval(start: T.date(23, 10), end: T.date(23, 11)),
            DateInterval(start: T.date(23, 10, 30), end: T.date(23, 12)),
            DateInterval(start: T.date(23, 12, 10), end: T.date(23, 13))
        ]
        XCTAssertEqual(FreeTimeFinder.gaps(in: window, busy: busy, minimum: 30 * 60), [
            DateInterval(start: T.date(23, 9), end: T.date(23, 10)),
            DateInterval(start: T.date(23, 13), end: T.date(23, 17))
        ], "overlaps merge; the 10-minute gap is too short")
    }

    // MARK: - find_events

    func testEventSearchMatchesTitlePlaceAndPeopleIgnoringCaseAndAccents() async throws {
        let context = T.context(events: [
            25: [T.event("Zahnarzt", day: 25, from: (8, 0), to: (9, 0), place: "Praxis Müller")],
            30: [T.event("1:1", day: 30, from: (11, 0), to: (11, 30), attendees: ["Zoë Adams"])],
            21: [T.event("Past 1:1", day: 21, from: (11, 0), to: (11, 30), attendees: ["Zoe Adams"])]
        ])
        let byPlace = try await run(EventSearchTool.make(context), ["text": .string("muller")])
        XCTAssertEqual(byPlace, """
        1 match “muller”:
        [[E1]] event Fri 25 Sep 08:00–09:00 Zahnarzt · Work · Praxis Müller
        \(AssistantFormat.referenceHint)
        """)

        let byPerson = try await run(EventSearchTool.make(context), ["text": .string("zoe")])
        XCTAssertTrue(byPerson.hasPrefix("2 matches “zoe”:"), byPerson)
        XCTAssertTrue(byPerson.contains("Past 1:1"), "any time, not only from today")
        XCTAssertLessThan(byPerson.range(of: "Past 1:1")!.lowerBound, byPerson.range(of: "Wed 30 Sep")!.lowerBound, "in date order")

        let none = try await run(EventSearchTool.make(context), ["text": .string("dentist"), "when": .string("next week")])
        XCTAssertEqual(none, "Nothing matches “dentist” · Monday 28 September 2026 – Sunday 4 October 2026.")
    }

    func testEventSearchTakesTheSearchFieldsOperators() async throws {
        let context = T.context(events: [
            24: [T.event("Refinement widok", day: 24, from: (10, 0), to: (11, 0), attendees: ["Anna Nowak", "Paweł Kowalski"])],
            25: [T.event("Daily", day: 25, from: (9, 0), to: (9, 15), place: "refinement room", attendees: ["Anna Nowak"])],
            28: [T.event("Planning", day: 28, from: (9, 0), to: (10, 0))]
        ])
        let titled = try await run(EventSearchTool.make(context), ["subject": .string("refinement")])
        XCTAssertTrue(titled.contains("Refinement widok") && !titled.contains("Daily"), "subject is the title only")
        let anywhere = try await run(EventSearchTool.make(context), ["text": .string("refinement")])
        XCTAssertTrue(anywhere.contains("Refinement widok") && anywhere.contains("Daily"))
        let withPawel = try await run(EventSearchTool.make(context), ["with": .string("Paweł")])
        XCTAssertTrue(withPawel.contains("Refinement widok") && !withPawel.contains("Daily"), withPawel)
        let onDay = try await run(EventSearchTool.make(context), ["day": .string("2026-09-28")])
        XCTAssertTrue(onDay.contains("Planning") && !onDay.contains("Daily"), "a date alone searches")
        let tasksOnly = try await run(EventSearchTool.make(context), ["text": .string("refinement"), "type": .string("task")])
        XCTAssertTrue(tasksOnly.hasPrefix("Nothing matches"), tasksOnly)
        let nothing = try await run(EventSearchTool.make(context), [:])
        XCTAssertTrue(nothing.hasPrefix("Say what to look for"))
    }

    func testEventSearchArgumentsBecomeTheFieldsQuery() {
        let arguments = AssistantToolArguments(["text": .string("plan"), "with": .string("Jon Nest"), "from": .string("me"),
                                                "between": .string("2026-09-01..2026-09-30")])
        XCTAssertEqual(EventSearchTool.operatorQuery(arguments), #"plan from:me with:"Jon Nest" between:2026-09-01..2026-09-30"#)
    }

    // MARK: - list_tasks

    func testTaskListFiltersByStateAndList() async throws {
        let context = T.context(tasks: [
            TaskItem(id: "1", title: "Renew passport", listID: "home", dueDate: T.date(20)),
            TaskItem(id: "2", title: "Someday idea", listID: "home"),
            TaskItem(id: "3", title: "Send invoice", listID: "work", dueDate: T.date(25), priority: .high),
            TaskItem(id: "4", title: "Filed taxes", listID: "home", isCompleted: true)
        ])
        let open = try await run(TaskListTool.make(context))
        XCTAssertEqual(open, """
        Open tasks in all lists (3):
        [[T1]] task Renew passport · due Sun 20 Sep · overdue · Home
        [[T2]] task Send invoice · due Fri 25 Sep · Work · high priority
        [[T3]] task Someday idea · Home
        \(AssistantFormat.referenceHint)
        """)

        let undatedHome = try await run(TaskListTool.make(context), ["filter": .string("undated"), "list": .string("home")])
        XCTAssertEqual(undatedHome, "Undated tasks in Home (1):\n[[T3]] task Someday idea · Home\n\(AssistantFormat.referenceHint)", "same task, same handle")

        let overdueWork = try await run(TaskListTool.make(context), ["filter": .string("overdue"), "list": .string("Work")])
        XCTAssertEqual(overdueWork, "No overdue tasks in Work.")

        let unknown = try await run(TaskListTool.make(context), ["list": .string("Groceries")])
        XCTAssertEqual(unknown, "No list named “Groceries”. Lists: Work, Home.")
    }

    func testLongAnswersAreCappedWithACount() {
        XCTAssertEqual(AssistantFormat.capped(["a", "b", "c", "d"], max: 2), "a\nb\n…and 2 more")
    }

    func testTheToolboxOffersItsDistinctlyNamedTools() {
        XCTAssertEqual(AssistantToolbox.readOnly(T.context()).map(\.name),
                       ["get_current_date", "get_agenda", "find_free_time", "find_events", "event_details", "list_tasks", "task_recurrence", "get_days"])
    }
}

extension AssistantCalendarToolsTests {
    func testHandlesInToolOutputResolveToTheStableObjects() async throws {
        let context = T.context(
            events: [24: [T.event("Standup", day: 24, from: (9, 0), to: (9, 30))]],
            tasks: [TaskItem(id: "reminder-1", title: "Send invoice", listID: "work", dueDate: T.date(24))]
        )
        _ = try await AgendaTool.make(context).call(AssistantToolArguments(["when": .string("tomorrow")]))

        XCTAssertEqual(context.references.reference(for: "E1"), .event(ChatEventReference(
            id: "Standup-24", day: T.date(24), snapshot: ChatObjectSnapshot(title: "Standup", detail: "09:00–09:30")
        )))
        XCTAssertEqual(context.references.reference(for: "T1"), .task(ChatTaskReference(
            id: "reminder-1", day: T.date(24), snapshot: ChatObjectSnapshot(title: "Send invoice", detail: "due Thu 24 Sep")
        )))
    }
}
