import XCTest
@testable import Shell
@testable import Intelligence

final class ChatSuggestionTests: XCTestCase {
    func testFourSuggestionsWithTheirSymbols() {
        XCTAssertEqual(ChatSuggestion.allCases.map(\.symbol), ["calendar", "clock", "exclamationmark.circle", "note.text"])
    }

    func testEverySuggestionIsTranslatedInEnglishAndPolish() throws {
        for language in ["en", "pl"] {
            let path = try XCTUnwrap((language == "en" ? ChatSuggestion.strings.path(forResource: language, ofType: "lproj") : Bundle.module.path(forResource: language, ofType: "lproj", inDirectory: "Localization")), "\(language).lproj is bundled")
            let bundle = try XCTUnwrap(Bundle(path: path))
            for suggestion in ChatSuggestion.allCases {
                for key in ["chip.\(suggestion.rawValue).label", "chip.\(suggestion.rawValue).prompt"] {
                    let text = bundle.localizedString(forKey: key, value: nil, table: nil)
                    XCTAssertNotEqual(text, key, "\(key) missing in \(language)")
                }
            }
        }
        let polish = try XCTUnwrap(Bundle(path: Bundle.module.path(forResource: "pl", ofType: "lproj", inDirectory: "Localization")!))
        XCTAssertEqual(polish.localizedString(forKey: "chip.agenda.label", value: nil, table: nil), "Agenda na dziś")
    }

    func testTheShownLabelIsResolvedNotTheKey() {
        XCTAssertFalse(ChatSuggestion.agenda.label.hasPrefix("chip."))
        XCTAssertNotEqual(ChatSuggestion.agenda.label, ChatSuggestion.agenda.prompt, "the prompt is the fuller question")
    }
}
