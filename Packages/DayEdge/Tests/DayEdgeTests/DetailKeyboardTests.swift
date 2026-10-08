import AppKit
import XCTest
@testable import Shell
@testable import UI

/// The details card's keys: only while a card is registered, only for
/// presses in its own window, never with ⌘ / ⌃ / ⌥ held.
@MainActor
final class DetailKeyboardTests: XCTestCase {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
                 backing: .buffered, defer: false)
    }

    private func key(_ code: UInt16, in window: NSWindow?, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                         windowNumber: window?.windowNumber ?? 0, context: nil, characters: "",
                         charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    func testKeysReachOnlyTheRegisteredCardsWindow() {
        let keyboard = DetailKeyboard()
        let card = window(), panel = window()
        var received: [DetailKeyboard.Key] = []
        XCTAssertFalse(keyboard.handle(key(125, in: card)), "nothing registered")

        keyboard.register(window: card) { received.append($0); return true }
        XCTAssertTrue(keyboard.handle(key(126, in: card)))
        XCTAssertTrue(keyboard.handle(key(125, in: card)))
        XCTAssertTrue(keyboard.handle(key(36, in: card)))
        XCTAssertTrue(keyboard.handle(key(53, in: card)))
        XCTAssertEqual(received, [.up, .down, .activate, .close])

        XCTAssertFalse(keyboard.handle(key(125, in: panel)), "another window's keys stay there")
        XCTAssertFalse(keyboard.handle(key(125, in: card, modifiers: .command)), "shortcuts pass through")
        XCTAssertFalse(keyboard.handle(key(0, in: card)), "other keys pass through")

        keyboard.unregister(window: panel)
        XCTAssertTrue(keyboard.handle(key(125, in: card)), "another window can't unregister the card")
        keyboard.unregister(window: card)
        XCTAssertFalse(keyboard.handle(key(125, in: card)))
    }

    func testAKeyTheCardDeclinesGoesThrough() {
        let keyboard = DetailKeyboard()
        let card = window()
        keyboard.register(window: card) { _ in false }
        XCTAssertFalse(keyboard.handle(key(36, in: card)))
    }

    func testNavigationClampsAndStartsAtTheEdges() {
        let navigation = DetailNavigation(rows: ["a", "b", "c"])
        XCTAssertEqual(navigation.move(from: nil, by: 1), "a")
        XCTAssertEqual(navigation.move(from: nil, by: -1), "c")
        XCTAssertEqual(navigation.move(from: "c", by: 1), "c")
        XCTAssertEqual(navigation.move(from: "a", by: -1), "a")
        XCTAssertEqual(navigation.move(from: "a", by: 1), "b")
    }
}
