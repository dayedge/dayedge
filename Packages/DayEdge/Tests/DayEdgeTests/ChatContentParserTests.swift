import XCTest
@testable import Shell
@testable import Intelligence

final class ChatContentParserTests: XCTestCase {
    private let day = Date(timeIntervalSinceReferenceDate: 0)
    private lazy var daily = ChatEventReference(id: "ev-daily", day: day, snapshot: .init(title: "Daily", detail: "10:30–10:55"))
    private lazy var invoice = ChatTaskReference(id: "task-invoice", day: day, snapshot: .init(title: "Send invoice", detail: nil))

    private func parse(_ text: String) -> [ChatContentPart] {
        ChatContentParser.parse(text) { handle in
            switch handle {
            case "E1": return .event(daily)
            case "T1": return .task(invoice)
            default: return nil
            }
        }
    }

    func testProseAndReferencesInterleaveInOrder() {
        XCTAssertEqual(parse("Friday looks light.\n\n[[E1]]\n\nAlso due:\n[[T1]]\nThat's all."), [
            .text("Friday looks light."),
            .event(daily),
            .text("Also due:"),
            .task(invoice),
            .text("That's all.")
        ])
    }

    func testTheModelsCopyOfTheLineIsDroppedWhateverItsBulletOrEmphasis() {
        for line in ["- [[E1]] 10:30–10:55 Daily · Work", "**[[E1]]** 10:30 Daily", "1. [[E1]] Daily", "  * [[E1]]"] {
            XCTAssertEqual(parse("Tomorrow:\n\(line)"), [.text("Tomorrow:"), .event(daily)], line)
        }
    }

    func testATokenInsideASentenceReadsAsTheTitle() {
        XCTAssertEqual(parse("Don't forget [[T1]] before [[E1]]."), [.text("Don't forget Send invoice before Daily.")])
    }

    func testUnknownHandlesNeverShowAsRawIDs() {
        XCTAssertEqual(parse("Here:\n[[E9]] Made up\nand [[T7]] too"), [.text("Here:\nand  too")])
    }

    func testAnUnfinishedTokenIsHeldBackWhileStreaming() {
        XCTAssertEqual(parse("Tomorrow:\n[[E"), [.text("Tomorrow:")])
        XCTAssertEqual(parse("Tomorrow:\n["), [.text("Tomorrow:")])
        XCTAssertEqual(parse("Tomorrow:\n[[E1]]"), [.text("Tomorrow:"), .event(daily)])
    }

    func testSeveralDayTokensOnOneLineAreSeveralDays() {
        let d1 = ChatDayReference(day: day, label: "Wigilia", isHoliday: true)
        let d2 = ChatDayReference(day: day.addingTimeInterval(86_400))
        let parts = ChatContentParser.parse("Święta:\n[[D1]] [[D2]] [[D9]]\nWolne.") { handle in
            switch handle {
            case "D1": return .day(d1)
            case "D2": return .day(d2)
            default: return nil
            }
        }
        XCTAssertEqual(parts, [.text("Święta:"), .day(d1), .day(d2), .text("Wolne.")], "an unknown day vanishes")
    }

    func testPlainProseIsOneTextPart() {
        XCTAssertEqual(parse("Nothing on tomorrow — enjoy."), [.text("Nothing on tomorrow — enjoy.")])
        XCTAssertEqual(parse(""), [])
    }
}

final class ChatReferenceRegistryTests: XCTestCase {
    func testHandlesAreStablePerObjectAndSeparatePerKind() {
        let registry = ChatReferenceRegistry()
        let day = Date(timeIntervalSinceReferenceDate: 0)
        let event = ChatObjectReference.event(.init(id: "a", day: day, snapshot: .init(title: "A")))
        let otherEvent = ChatObjectReference.event(.init(id: "b", day: day, snapshot: .init(title: "B")))
        let task = ChatObjectReference.task(.init(id: "a", day: day, snapshot: .init(title: "Task A")))

        XCTAssertEqual(registry.handle(for: event), "E1")
        XCTAssertEqual(registry.handle(for: otherEvent), "E2")
        XCTAssertEqual(registry.handle(for: task), "T1")
        XCTAssertEqual(registry.handle(for: event), "E1", "the same object keeps its handle")
        XCTAssertEqual(registry.reference(for: "T1"), task)
        XCTAssertNil(registry.reference(for: "E3"))
        XCTAssertEqual(ChatReferenceRegistry.token("E1"), "[[E1]]")
    }
}

final class ChatProseTests: XCTestCase {
    func testInlineMarkdownRendersAndHeadingsBecomeBoldLines() {
        let styled = ChatProse.attributed("### Friday\nLooks **light**.")
        XCTAssertEqual(String(styled.characters), "Friday\nLooks light.")
        let bold = styled.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map { String(styled[$0.range].characters) }
        XCTAssertEqual(bold, ["Friday", "light"])
    }

    func testPlainTextPassesThrough() {
        XCTAssertEqual(String(ChatProse.attributed("No events tomorrow.").characters), "No events tomorrow.")
    }
}
