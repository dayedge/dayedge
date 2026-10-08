import XCTest
@testable import Shell
@testable import Intelligence

/// `get_days` and day references in tool output. Reference: Wednesday
/// 23 September 2026 12:00 UTC.
final class DaysToolTests: XCTestCase {
    private typealias T = AssistantTestData
    private let christmas = ["2026-12-24": "Wigilia", "2026-12-25": "Boże Narodzenie", "2026-12-26": "Drugi dzień świąt"]

    private func run(_ context: AssistantToolContext, _ when: String) async throws -> String {
        try await DaysTool.make(context).call(AssistantToolArguments(["when": .string(when)]))
    }

    func testAShortSpanListsEveryDayWithWhatItIs() async throws {
        let context = T.context(holidays: christmas)
        let answer = try await run(context, "2026-12-24..2026-12-28")
        let lines = answer.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[0].hasPrefix("Days in Thursday 24 December 2026 – Monday 28 December 2026 (holidays for "), lines[0])
        XCTAssertEqual(Array(lines[1...5]), [
            "[[D1]] Thu 24 Dec 2026 · Wigilia (public holiday)",
            "[[D2]] Fri 25 Dec 2026 · Boże Narodzenie (public holiday)",
            "[[D3]] Sat 26 Dec 2026 · Drugi dzień świąt (public holiday) · weekend",
            "[[D4]] Sun 27 Dec 2026 · weekend",
            "[[D5]] Mon 28 Dec 2026 · workday"
        ])
        XCTAssertEqual(lines.last, DaysTool.dayHint)

        XCTAssertEqual(context.references.reference(for: "D1"),
                       .day(ChatDayReference(day: T.date(24, month: 12), label: "Wigilia", isHoliday: true)))
        XCTAssertEqual(context.references.reference(for: "D3"),
                       .day(ChatDayReference(day: T.date(26, month: 12), label: "Drugi dzień świąt", isHoliday: true, isWeekend: true)),
                       "a weekend holiday keeps both facts; the renderer applies the grid's precedence")
    }

    func testALongPeriodListsOnlyTheHolidays() async throws {
        let answer = try await run(T.context(holidays: christmas), "2026-10-01..2026-12-31")
        let days = answer.split(separator: "\n").filter { $0.hasPrefix("[[D") }
        XCTAssertEqual(days.count, 3)
        XCTAssertTrue(answer.hasPrefix("Public holidays in Thursday 1 October 2026 – Thursday 31 December 2026"), answer)
    }

    func testTheAgendaNamesAHolidayEvenWithNothingScheduled() async throws {
        let answer = try await AgendaTool.make(T.context(holidays: christmas))
            .call(AssistantToolArguments(["when": .string("2026-12-25")]))
        XCTAssertTrue(answer.contains("[[D1]] Friday 25 December 2026 · Boże Narodzenie (public holiday)"), answer)
    }

    func testTheOnDeviceTierGetsPlainDaysWithoutReferences() async throws {
        var context = T.context(holidays: christmas)
        context.showsReferences = false
        let answer = try await run(context, "2026-12-24..2026-12-25")
        XCTAssertFalse(answer.contains("[["), answer)
        XCTAssertTrue(answer.contains("Thu 24 Dec 2026 · Wigilia (public holiday)"), answer)
    }
}
