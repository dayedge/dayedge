import XCTest
@testable import Shell
@testable import Intelligence

final class ChatTimelineTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func at(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    func testTheSameDayIsLeftAlone() {
        let messages = [
            ChatMessage(role: .user, text: "today?", sentAt: at(day: 29, hour: 9)),
            ChatMessage(role: .assistant, text: "Two meetings.", sentAt: at(day: 29, hour: 9)),
            ChatMessage(role: .user, text: "tomorrow?", sentAt: at(day: 29, hour: 23))
        ]
        XCTAssertEqual(ChatTimeline.dated(messages, calendar: calendar).map(\.text), messages.map(\.text))
    }

    func testTheFirstQuestionOfANewDayIsMarked() {
        let messages = [
            ChatMessage(role: .user, text: "tomorrow?", sentAt: at(day: 29, hour: 16)),
            ChatMessage(role: .assistant, text: "The dentist at 8.", sentAt: at(day: 29, hour: 16)),
            ChatMessage(role: .user, text: "and today?", sentAt: at(day: 30, hour: 9)),
            ChatMessage(role: .assistant, text: "Nothing.", sentAt: at(day: 30, hour: 9)),
            ChatMessage(role: .user, text: "thanks", sentAt: at(day: 30, hour: 10))
        ]
        let dated = ChatTimeline.dated(messages, calendar: calendar).map(\.text)
        XCTAssertEqual(dated[0], "tomorrow?")
        XCTAssertEqual(dated[1], "The dentist at 8.", "answers are never rewritten")
        XCTAssertTrue(dated[2].hasPrefix("[It is now "))
        XCTAssertTrue(dated[2].contains("2026"))
        XCTAssertTrue(dated[2].hasSuffix("\n\nand today?"))
        XCTAssertEqual(dated[4], "thanks", "only where the day changes")
    }

    func testCurrentDateToolReadsTheClock() {
        let text = CurrentDateTool.answer(now: at(day: 30, hour: 9), calendar: calendar)
        XCTAssertTrue(text.contains("(2026-09-30, time zone Europe/Warsaw)"), text)
        XCTAssertTrue(text.contains("09:00"), text)
        XCTAssertTrue(text.contains("This week: 2026-09-28 to 2026-10-04") || text.contains("This week: 2026-09-27 to 2026-10-03"), text)
        XCTAssertTrue(text.contains("Tomorrow: "), text)
    }

    func testInstructionsSayTheCurrentDateAndTheDayChangeRule() {
        let full = AssistantInstructions.full(now: at(day: 30, hour: 9), calendar: calendar)
        XCTAssertTrue(full.contains("(2026-09-30), 09:00"))
        XCTAssertTrue(full.contains("Never carry a date over"))
        XCTAssertTrue(full.contains("get_current_date"))
        let onDevice = AssistantInstructions.onDevice(now: at(day: 30, hour: 9), calendar: calendar)
        XCTAssertTrue(onDevice.contains("get_current_date"))
        XCTAssertTrue(onDevice.contains("never reuse a date"))
    }
}
