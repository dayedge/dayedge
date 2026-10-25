import XCTest
@testable import Domain
@testable import Intelligence

/// `#tag` completion: what a tag being typed offers, and the text once one is chosen.
@MainActor
final class TagCompletionTests: XCTestCase {
    private let lists = [CalendarSource(id: "work", title: "Work", tint: .blue),
                         CalendarSource(id: "home", title: "Home", tint: .green)]
    private let calendars = [CalendarSource(id: "team", title: "Team Alpha", tint: .orange),
                             CalendarSource(id: "workshop", title: "Workshops", tint: .purple)]

    private func completion(_ query: String) -> TagCompletion? {
        TagCompletion(query: query, lists: lists, calendars: calendars)
    }

    private func titles(_ query: String) -> [String] {
        completion(query)?.options.map(\.source.title) ?? []
    }

    func testATagAtTheEndOffersWhatItCanName() {
        XCTAssertEqual(titles("lunch #"), ["Work", "Home", "Team Alpha", "Workshops"], "lists, then calendars")
        XCTAssertEqual(titles("lunch #wo"), ["Work", "Workshops"])
        XCTAssertEqual(titles("lunch #TEAMa"), ["Team Alpha"], "case and spaces ignored, as the parser matches")
        XCTAssertEqual(titles("lunch #alpha"), ["Team Alpha"], "a name containing it, after those starting with it")
        XCTAssertEqual(completion("lunch #wo")?.options.map(\.kinds), [[.list], [.calendar]])
    }

    func testOneTagForAListAndACalendarOfTheSameName() {
        let both = TagCompletion(query: "#wo", lists: lists, calendars: [CalendarSource(id: "cal-work", title: "work", tint: .red)])
        XCTAssertEqual(both?.options.map(\.tag), ["#Work"], "one tag names both, as the parser reads it")
        XCTAssertEqual(both?.options.first?.kinds, [.list, .calendar])
    }

    func testATagThatWouldNotReadBackIsNotOffered() {
        let odd = [CalendarSource(id: "misc", title: "Misc.", tint: .gray),
                   CalendarSource(id: "errands", title: "Errands (Home)", tint: .gray)]
        XCTAssertNil(TagCompletion(query: "#", lists: odd, calendars: []), "the parser trims a word's end punctuation")
    }

    func testEveryMatchIsOfferedPastTheVisibleRows() throws {
        let many = (1...10).map { CalendarSource(id: "l\($0)", title: "List \($0)", tint: .blue) }
        var completion = try XCTUnwrap(TagCompletion(query: "#", lists: many, calendars: []))
        XCTAssertEqual(completion.options.count, 10, "more than are shown at once; the rest scroll")
        completion.move(9)
        XCTAssertEqual(completion.selectedOption.source.title, "List 10")
    }

    func testNoCompletionOutsideATagBeingTyped() {
        XCTAssertNil(completion("lunch"))
        XCTAssertNil(completion("lunch #work "), "a space ends the tag")
        XCTAssertNil(completion("#work lunch"), "only the tag at the end, where typing is")
        XCTAssertNil(completion("lunch #xyz"), "nothing it can name")
        XCTAssertNil(completion("lunch #home"), "already the only name it can be")
        XCTAssertNotNil(completion("lunch #work"), "Work, but Workshops too")
    }

    func testChoosingWritesTheTagWithoutSpaces() throws {
        var completion = try XCTUnwrap(completion("lunch tomorrow #te"))
        XCTAssertEqual(completion.completed(), "lunch tomorrow #TeamAlpha ")
        completion = try XCTUnwrap(self.completion("lunch #wo"))
        completion.move(1)
        XCTAssertEqual(completion.selectedOption.source.title, "Workshops")
        completion.move(5)
        XCTAssertEqual(completion.selectedOption.source.title, "Workshops", "stops at the end")
        XCTAssertEqual(completion.completed(), "lunch #Workshops ")
        XCTAssertEqual(completion.completed(with: completion.options[0]), "lunch #Work ", "a click on another")
    }

    func testThePaletteCompletesAsTyped() {
        let palette = SearchPaletteModel(findTemporal: { _, _, _ in nil }, parse: { _, _, _, _, _ in [] }, prepareParser: { _ in })
        palette.typingPause = .zero
        palette.taskLists = { [lists] in lists }
        palette.writableCalendars = calendars

        palette.update(query: "lunch #wo")
        XCTAssertEqual(palette.tagCompletion?.options.count, 2, "at once, not after the typing pause")
        XCTAssertEqual(palette.keyHints, SearchPaletteModel.tagCompletionHints)
        palette.moveSelection(1)
        XCTAssertEqual(palette.completeTag(), "lunch #Workshops ")
        XCTAssertNil(palette.tagCompletion)
        XCTAssertNil(palette.completeTag(), "nothing to complete: Tab and Return do what they usually do")

        palette.update(query: "lunch #h")
        XCTAssertTrue(palette.dismissTagCompletion(), "Esc hides it")
        XCTAssertFalse(palette.dismissTagCompletion())
        palette.update(query: "lunch #ho")
        XCTAssertNotNil(palette.tagCompletion, "typing on brings it back")
        palette.isResultsViewShown = true
        palette.update(query: "lunch #hom")
        XCTAssertNil(palette.tagCompletion, "only over the actions, not in the Search view")
    }
}
