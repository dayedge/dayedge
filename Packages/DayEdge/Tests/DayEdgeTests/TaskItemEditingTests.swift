import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class TaskItemEditingTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()
    private lazy var day = calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!)
    private lazy var at14 = calendar.date(byAdding: .hour, value: 14, to: day)!

    private func base(due: Date? = nil, time: Bool = false) -> TaskItem {
        TaskItem(id: "t", title: "Milk", notes: "2 litres", listID: "groceries", dueDate: due, hasDueTime: time)
    }

    func testSimpleFieldsApply() {
        let url = URL(string: "https://example.com")!
        var task = base()
        task = task.applying(.title("Oat milk"))
        task = task.applying(.notes("Barista edition"))
        task = task.applying(.url(url))
        task = task.applying(.priority(.high))
        task = task.applying(.list("home"))
        XCTAssertEqual(task.title, "Oat milk")
        XCTAssertEqual(task.notes, "Barista edition")
        XCTAssertEqual(task.url, url)
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.listID, "home")
    }

    func testEmptyTitleIsRefusedAndBlankNotesBecomeNil() {
        let task = base()
        XCTAssertEqual(task.applying(.title("   ")).title, "Milk")
        XCTAssertNil(task.applying(.notes("  \n ")).notes)
        XCTAssertNil(task.applying(.notes(nil)).notes)
    }

    func testCompletionStampsAndClearsTheDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let done = base().applying(.completed(true), now: now)
        XCTAssertTrue(done.isCompleted)
        XCTAssertEqual(done.completionDate, now)
        XCTAssertNil(done.applying(.completed(false)).completionDate)
    }

    func testRepeatNeedsADate() {
        XCTAssertEqual(base().applying(.recurrence(.weekly)).recurrence, .never)
        XCTAssertEqual(base(due: day).applying(.recurrence(.weekly)).recurrence, .weekly)
    }

    func testClearingTheDateClearsRepeat() {
        var task = base(due: day).applying(.recurrence(.monthly))
        task = task.applying(.due(nil, hasTime: false))
        XCTAssertNil(task.dueDate)
        XCTAssertEqual(task.recurrence, .never)
        XCTAssertFalse(task.hasDueTime)
    }

    func testRelativeAlertsNeedADueTime() {
        let dateOnly = base(due: day).applying(.alert(.relative(minutesBefore: 15)))
        XCTAssertNil(dateOnly.alert) // refused: nothing to be relative to
        let timed = base(due: at14, time: true).applying(.alert(.relative(minutesBefore: 15)))
        XCTAssertEqual(timed.alert, .relative(minutesBefore: 15))
        XCTAssertEqual(base().applying(.alert(.absolute(day))).alert, .absolute(day)) // absolute is always fine
    }

    func testRemovingTheTimeKeepsTheAlertAsTheSameMoment() {
        let timed = base(due: at14, time: true).applying(.alert(.relative(minutesBefore: 30)))
        let dateOnly = timed.applying(.due(day, hasTime: false))
        XCTAssertEqual(dateOnly.alert, .absolute(at14.addingTimeInterval(-30 * 60)))
        let cleared = timed.applying(.due(nil, hasTime: false))
        XCTAssertEqual(cleared.alert, .absolute(at14.addingTimeInterval(-30 * 60)))
    }

    func testMovingTheDateKeepsARelativeAlert() {
        let timed = base(due: at14, time: true).applying(.alert(.relative(minutesBefore: 15)))
        let later = timed.applying(.due(at14.addingTimeInterval(86_400), hasTime: true))
        XCTAssertEqual(later.alert, .relative(minutesBefore: 15))
    }

    func testCustomRecurrenceSurvivesUnrelatedEdits() {
        var task = base(due: day)
        task.recurrence = .custom("Every 3 months")
        let edited = task.applying(.priority(.low)).applying(.title("Filter")).applying(.notes("x"))
        XCTAssertEqual(edited.recurrence, .custom("Every 3 months"))
        XCTAssertTrue(edited.isRecurring)
    }

    func testAlertTitles() {
        XCTAssertEqual(TaskAlert.relative(minutesBefore: 0).title, "At time of due date")
        XCTAssertEqual(TaskAlert.relative(minutesBefore: 15).title, "15 min before")
        XCTAssertEqual(TaskAlert.relative(minutesBefore: 60).title, "1 hour before")
        XCTAssertEqual(TaskAlert.relative(minutesBefore: 1440).title, "1 day before")
    }

    func testShortcutRuleLetsPopoverTextFieldsOwnTheKeyboard() {
        typealias Monitor = ActionShortcutMonitor
        // Typing in a popover field: the field owns every key, including
        // Esc (which cancels the edit rather than closing the popover).
        XCTAssertFalse(Monitor.shouldHandle(.completeSelectedTask, inChildWindow: true, isTextEditing: true))
        XCTAssertFalse(Monitor.shouldHandle(.openEventDetails, inChildWindow: true, isTextEditing: true))
        XCTAssertFalse(Monitor.shouldHandle(.escapeSearch, inChildWindow: true, isTextEditing: true))
        // Not typing, or in the main window: routing unchanged.
        XCTAssertTrue(Monitor.shouldHandle(.completeSelectedTask, inChildWindow: true, isTextEditing: false))
        XCTAssertTrue(Monitor.shouldHandle(.completeSelectedTask, inChildWindow: false, isTextEditing: true))
    }
}
