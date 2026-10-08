import AppKit
import XCTest
@testable import Domain
@testable import UI

/// Key representation: recorded and matched the same way.
final class KeyboardCommandTests: XCTestCase {
    func testIncidentalFlagsNeverCount() {
        let plain = KeyboardCommand(keyCode: 38, baseCharacter: "j", modifierFlags: .command)
        let noisy = KeyboardCommand(keyCode: 38, baseCharacter: "j", modifierFlags: [.command, .capsLock, .function, .numericPad])
        XCTAssertEqual(plain, noisy)
        XCTAssertEqual(plain, KeyboardCommand(key: "j"))
    }

    func testShiftAndOptionKeepTheBaseKey() {
        XCTAssertEqual(KeyboardCommand(keyCode: 19, baseCharacter: "2", modifierFlags: [.command, .shift])?.displayLabel, "⇧⌘2")
        XCTAssertEqual(KeyboardCommand(keyCode: 38, baseCharacter: "j", modifierFlags: [.command, .option])?.displayLabel, "⌥⌘J")
    }

    func testSpecialKeysGoByKeyCodeAndUnusableKeysAreRefused() {
        let tab = KeyboardCommand(keyCode: 48, baseCharacter: "\t", modifierFlags: .control)
        XCTAssertEqual(tab?.keyCode, 48)
        XCTAssertEqual(tab?.displayLabel, "⌃⇥")
        XCTAssertNil(KeyboardCommand(keyCode: 33, baseCharacter: "", modifierFlags: .command), "a dead key")
        XCTAssertNil(KeyboardCommand(keyCode: 200, baseCharacter: "\u{F710}", modifierFlags: .command), "a function-key code point")
    }

    func testRoundTripsThroughStorage() throws {
        for shortcut in [KeyboardCommand(key: "c", modifiers: [.command, .shift]), KeyboardCommand(keyCode: 123, modifiers: .shift)] {
            XCTAssertEqual(try JSONDecoder().decode(KeyboardCommand.self, from: JSONEncoder().encode(shortcut)), shortcut)
        }
    }

    func testAKeyPressMatchesTheShortcutItDisplays() throws {
        let event = try XCTUnwrap(Self.key(38, "j", [.command]))
        XCTAssertEqual(KeyboardCommand(event: event), KeyboardCommand(key: "j"))
        XCTAssertNotEqual(KeyboardCommand(event: event), KeyboardCommand(key: "j", modifiers: [.command, .shift]))
    }

    static func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags, isARepeat: Bool = false) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: isARepeat, keyCode: code)
    }
}

@MainActor
final class KeyboardShortcutSettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "KeyboardShortcutSettingsTests.\(UUID())")
    }

    private func store() -> KeyboardShortcutSettings { KeyboardShortcutSettings(defaults: defaults) }
    private let join = ShortcutCommand.action(.joinSelectedMeeting)
    private let sort = ShortcutCommand.action(.openSortMenu)

    // MARK: Defaults and changes

    func testDefaultsAndSortTasksUnassigned() {
        let settings = store()
        XCTAssertEqual(settings.shortcut(for: join)?.displayLabel, "⌘J")
        XCTAssertEqual(settings.shortcut(for: .viewMode(.ask))?.displayLabel, "⌘4")
        XCTAssertNil(settings.shortcut(for: sort), "⌘S is Save everywhere else")
        XCTAssertFalse(settings.hasCustomizations)
    }

    func testOneKeyOneCommand() {
        let bindings = Array(store().effective.values)
        XCTAssertEqual(Set(bindings).count, bindings.count)
    }

    func testOverrideClearResetAndRestart() {
        let settings = store()
        settings.set(KeyboardCommand(key: "k"), for: join)
        XCTAssertEqual(settings.shortcut(for: join)?.displayLabel, "⌘K")
        XCTAssertTrue(settings.isCustomized(join))
        XCTAssertEqual(store().shortcut(for: join)?.displayLabel, "⌘K", "survives a restart")

        settings.clear(join)
        XCTAssertNil(settings.shortcut(for: join))
        XCTAssertNil(store().shortcut(for: join), "cleared stays cleared — the default doesn't come back")

        settings.reset(join)
        XCTAssertEqual(settings.shortcut(for: join)?.displayLabel, "⌘J")
        XCTAssertFalse(settings.isCustomized(join))
    }

    func testRestoreDefaultsTouchesOnlyShortcuts() {
        defaults.set(true, forKey: "unrelated")
        let settings = store()
        settings.set(KeyboardCommand(key: "k"), for: join)
        settings.set(KeyboardCommand(key: "s"), for: sort)
        settings.resetAll()
        XCTAssertEqual(settings.shortcut(for: join)?.displayLabel, "⌘J")
        XCTAssertNil(settings.shortcut(for: sort))
        XCTAssertTrue(defaults.bool(forKey: "unrelated"))
    }

    func testFixedCommandsIgnoreOverrides() {
        let settings = store()
        settings.set(KeyboardCommand(key: "k"), for: .action(.previousDay))
        XCTAssertEqual(settings.shortcut(for: .action(.previousDay))?.displayLabel, "⇧←")
    }

    // MARK: Recovery

    private func storeRaw(_ object: Any) {
        defaults.set(try? JSONSerialization.data(withJSONObject: object), forKey: KeyboardShortcutSettings.defaultsKey)
    }

    func testUnknownIdsArePreservedAndInvalidEntriesFallBack() throws {
        storeRaw(["action.fromTheFuture": ["key": "q", "modifierBits": 1_048_576],
                  join.id: ["key": "k"]])   // missing modifiers: invalid
        let settings = store()
        XCTAssertEqual(settings.shortcut(for: join)?.displayLabel, "⌘J", "the default, not a broken binding")
        settings.set(KeyboardCommand(key: "k"), for: sort)
        let saved = try XCTUnwrap(defaults.data(forKey: KeyboardShortcutSettings.defaultsKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertNotNil(object["action.fromTheFuture"], "a newer version's entry survives")
    }

    func testCorruptedDataMeansDefaults() {
        defaults.set(Data("not json".utf8), forKey: KeyboardShortcutSettings.defaultsKey)
        XCTAssertEqual(store().shortcut(for: join)?.displayLabel, "⌘J")
    }

    func testIneligibleStoredOverrideIsIgnored() throws {
        let plainJ = try JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyboardCommand(key: "j", modifiers: [])))
        storeRaw([join.id: plainJ])
        XCTAssertEqual(store().shortcut(for: join)?.displayLabel, "⌘J")
    }

    func testCollidingOverridesLeaveExactlyOneBound() throws {
        let commandK = try JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyboardCommand(key: "k")))
        storeRaw([join.id: commandK, sort.id: commandK])
        let settings = store()
        let owners = ShortcutCommand.commands.filter { settings.shortcut(for: $0) == KeyboardCommand(key: "k") }
        XCTAssertEqual(owners.count, 1)
    }

    func testADefaultTakenByAnOverrideIsLeftUnassigned() {
        let settings = store()
        settings.set(KeyboardCommand(key: "f"), for: join)   // Focus Search's default
        XCTAssertEqual(settings.shortcut(for: join)?.displayLabel, "⌘F")
        XCTAssertNil(settings.shortcut(for: .action(.focusSearch)), "never two commands on one key")
    }

    // MARK: Validation (eligibility, then collision)

    func testEligibility() {
        XCTAssertEqual(KeyboardShortcutSettings.eligibility(KeyboardCommand(key: "j", modifiers: [])), .needsCommandOrControl)
        XCTAssertEqual(KeyboardShortcutSettings.eligibility(KeyboardCommand(key: "j", modifiers: [.option, .shift])), .needsCommandOrControl)
        XCTAssertEqual(KeyboardShortcutSettings.eligibility(KeyboardCommand(keyCode: 200, modifiers: .command)), .unsupportedKey)
        XCTAssertEqual(KeyboardShortcutSettings.eligibility(KeyboardCommand(key: "q")), .reservedBySystem)
        XCTAssertEqual(KeyboardShortcutSettings.eligibility(KeyboardCommand(key: "c")), .reservedBySystem, "the search field copies")
        XCTAssertNil(KeyboardShortcutSettings.eligibility(KeyboardCommand(key: "s")), "conventional, but allowed")
        XCTAssertNil(KeyboardShortcutSettings.eligibility(KeyboardCommand(key: "k", modifiers: .control)))
    }

    func testCollisions() {
        let settings = store()
        XCTAssertEqual(settings.collision(KeyboardCommand(key: "f"), for: join), .command(.action(.focusSearch)))
        XCTAssertEqual(settings.collision(KeyboardCommand(keyCode: 123, modifiers: .shift), for: join),
                       .command(.action(.previousDay)), "a fixed navigation key")
        XCTAssertEqual(settings.collision(KeyboardCommand(keyCode: 36, modifiers: .command), for: join)?.title,
                       KeyboardCommands.fixedKeys.first { $0.shortcut == KeyboardCommand(keyCode: 36, modifiers: .command) }?.owner,
                       "Ask's Allow")
        XCTAssertNil(settings.collision(KeyboardCommand(key: "j"), for: join), "its own key")
        XCTAssertNil(settings.collision(KeyboardCommand(key: "s"), for: sort))
        XCTAssertEqual(settings.collision(KeyboardCommand(key: "]"), for: sort), .command(.action(.nextOccurrence)),
                       "the panel's ⌘] — Settings' own ⌘] is another window")
    }

    // MARK: Dispatch

    private func resolve(_ settings: KeyboardShortcutSettings, _ event: NSEvent?, recording: Bool = false,
                         tracking: Bool = false) -> ShortcutCommand? {
        event.flatMap { settings.resolve($0, isRecording: recording, isMenuTracking: tracking) }
    }

    func testRebindingTakesEffectAtOnce() {
        let settings = store()
        XCTAssertEqual(resolve(settings, KeyboardCommandTests.key(38, "j", .command)), join)
        settings.set(KeyboardCommand(key: "k"), for: join)
        XCTAssertEqual(resolve(settings, KeyboardCommandTests.key(40, "k", .command)), join)
        XCTAssertNil(resolve(settings, KeyboardCommandTests.key(38, "j", .command)), "the old key does nothing")
    }

    func testNothingRunsWhileRecordingInAMenuOnRepeatOrUnbound() {
        let settings = store()
        let commandJ = KeyboardCommandTests.key(38, "j", .command)
        XCTAssertNil(resolve(settings, commandJ, recording: true))
        XCTAssertNil(resolve(settings, commandJ, tracking: true), "an open menu runs its own key equivalent")
        XCTAssertNil(resolve(settings, KeyboardCommandTests.key(38, "j", .command, isARepeat: true)), "no repeated Join")
        XCTAssertNil(resolve(settings, KeyboardCommandTests.key(1, "s", .command)), "Sort Tasks is unassigned")
        XCTAssertEqual(resolve(settings, KeyboardCommandTests.key(124, "\u{F703}", .shift, isARepeat: true)),
                       .action(.nextDay), "navigation keeps repeating")
    }

    func testAKeyThatDoesNothingIsNotTaken() throws {
        let event = try XCTUnwrap(KeyboardCommandTests.key(38, "j", .command))
        XCTAssertNil(ActionShortcutMonitor.Coordinator.outcome(of: event, handled: true))
        XCTAssertTrue(ActionShortcutMonitor.Coordinator.outcome(of: event, handled: false) === event)
    }

    func testMenusAndHandlersAgreeAfterARestart() {
        let settings = store()
        settings.set(KeyboardCommand(key: "k", modifiers: [.command, .option]), for: join)
        let restarted = store()
        for command in ShortcutCommand.commands {
            XCTAssertEqual(restarted.shortcut(for: command), settings.shortcut(for: command))
        }
        XCTAssertEqual(restarted.shortcut(for: join)?.swiftUIShortcut?.key, "k")
    }
}

/// The selected event, as it is now.
final class SelectedEventTests: XCTestCase {
    func testAStaleSelectionFindsNothing() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let event = AgendaEventModel(startDate: start, endDate: start.addingTimeInterval(1800), title: "Standup")
        let selection = AgendaKeyboardSelection(date: start, event: event)
        XCTAssertEqual(selection.current(in: [event])?.id, event.id)
        XCTAssertNil(selection.current(in: []), "deleted")
        let moved = AgendaEventModel(id: event.id, startDate: start.addingTimeInterval(3600),
                                     endDate: start.addingTimeInterval(5400), title: "Standup")
        XCTAssertNil(selection.current(in: [moved]), "moved")
    }
}

/// Recording: what each key does, and the shared state.
@MainActor
final class ShortcutRecorderTests: XCTestCase {
    private func decide(_ code: UInt16, _ base: String?, _ flags: NSEvent.ModifierFlags,
                        problem: String? = nil) -> ShortcutRecorderDecision {
        ShortcutRecorderDecision.decide(keyCode: code, baseCharacter: base, modifierFlags: flags) { _ in problem }
    }

    func testKeys() {
        XCTAssertEqual(decide(53, "\u{1B}", []), .cancel, "Esc keeps the old shortcut")
        XCTAssertEqual(decide(51, "\u{7F}", []), .clear, "⌫ removes it")
        XCTAssertEqual(decide(38, "j", [.command, .option]), .assign(KeyboardCommand(key: "j", modifiers: [.command, .option])))
        XCTAssertEqual(decide(3, "f", .command, problem: "Already used for Focus Search"), .reject("Already used for Focus Search"),
                       "keeps listening")
        if case .reject = decide(33, "", .command) {} else { XCTFail("a dead key is refused") }
    }

    func testRecordingStateIsOneAtATime() {
        let recording = ShortcutRecording()
        recording.begin(.action(.joinSelectedMeeting))
        XCTAssertTrue(recording.isActive)
        recording.end(.action(.focusSearch))
        XCTAssertTrue(recording.isActive, "another recorder's end leaves this one")
        recording.end(.action(.joinSelectedMeeting))
        XCTAssertFalse(recording.isActive)
    }
}
