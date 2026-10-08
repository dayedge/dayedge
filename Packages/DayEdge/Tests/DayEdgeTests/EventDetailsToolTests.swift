import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// `event_details`. Reference: Wednesday 23 September 2026 12:00 UTC.
final class EventDetailsToolTests: XCTestCase {
    private typealias T = AssistantTestData

    private let review = AgendaEventModel(
        id: "review-24", startTime: "14:00", endTime: "15:00",
        startDate: T.date(24, 14), endDate: T.date(24, 15),
        title: "Sprint review", subtitle: "Room 4", status: .tentative, calendarName: "Work",
        notes: "Demo the new sync.",
        attendees: [
            EventAttendee(name: "Anna", status: .accepted),
            EventAttendee(name: "Me", status: .tentative, isCurrentUser: true),
            EventAttendee(name: "Bob", status: .pending),
            EventAttendee(name: "", status: .declined, email: "cara@example.com")
        ],
        myResponseStatus: .tentative,
        organizerName: "Anna"
    )

    private func run(_ context: AssistantToolContext, _ arguments: [String: JSONValue]) async throws -> String {
        try await EventDetailsTool.make(context).call(AssistantToolArguments(arguments))
    }

    func testShowsAttendeesTheirResponsesYoursAndTheNotes() async throws {
        let answer = try await run(T.context(events: [24: [review]]), ["event": .string("sprint review")])
        XCTAssertEqual(answer, """
        [[E1]] event Thu 24 Sep 14:00–15:00 Sprint review · Work · Room 4 · tentative
        When: Thursday 24 September 2026, 14:00–15:00
        Where: Room 4
        Calendar: Work
        Organizer: Anna
        Your response: maybe
        Attendees (4): 1 accepted, 1 maybe, 1 not responded, 1 declined
        - Me (you) · maybe
        - Anna (organizer) · accepted
        - Bob · not responded
        - cara@example.com · declined
        Notes:
        Demo the new sync.
        \(AssistantFormat.referenceHint)
        """)
    }

    func testAReferenceFromAnEarlierAnswerFindsTheSameEvent() async throws {
        let context = T.context(events: [24: [review]])
        _ = try await AgendaTool.make(context).call(AssistantToolArguments(["when": .string("tomorrow")])) // mints E1
        let answer = try await run(context, ["event": .string("[[E1]]")])
        XCTAssertTrue(answer.contains("Organizer: Anna"), answer)
    }

    func testARepeatingEventResolvesToItsNextOccurrence() async throws {
        let daily = { (day: Int) in T.event("Daily", day: day, from: (10, 30), to: (10, 55)) }
        let context = T.context(events: [22: [daily(22)], 23: [daily(23)], 24: [daily(24)]])
        let answer = try await run(context, ["event": .string("daily")])
        XCTAssertTrue(answer.contains("When: Thursday 24 September 2026, 10:30–10:55"),
                      "today's 10:30 has passed at noon, so tomorrow's: \(answer)")
    }

    func testDifferentMatchesAskWhichAndMissingOnesSaySo() async throws {
        let context = T.context(events: [24: [review, T.event("Sprint planning", day: 24, from: (9, 0), to: (10, 0))]])
        let several = try await run(context, ["event": .string("sprint")])
        XCTAssertTrue(several.hasPrefix("Several events match “sprint”; which one?"), several)

        let missing = try await run(context, ["event": .string("offsite")])
        XCTAssertEqual(missing, "No event matching “offsite”.")
    }

    func testYourOwnEventWithoutInviteesAndLongNotes() async throws {
        let focus = AgendaEventModel(id: "focus", startTime: "08:00", endTime: "09:00", startDate: T.date(24, 8), endDate: T.date(24, 9),
                                     title: "Focus", calendarName: "Home", notes: String(repeating: "x", count: 1_500))
        let answer = try await run(T.context(events: [24: [focus]]), ["event": .string("focus")])
        XCTAssertTrue(answer.contains("Your response: your own event, no invitees"), answer)
        XCTAssertTrue(answer.contains("Attendees: none listed."), answer)
        XCTAssertTrue(answer.contains(" …(notes shortened)"), answer)
    }
}
