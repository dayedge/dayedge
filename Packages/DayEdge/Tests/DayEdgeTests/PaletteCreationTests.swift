import XCTest
@testable import Domain
@testable import Intelligence

/// New Event / New Task (⌘N, ⇧⌘N): Quick Add on an empty draft, never parsed.
@MainActor
final class PaletteCreationTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    private var reference: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12, minute: 20))! }

    private var parsed = 0
    private var createdTasks: [TaskDraft] = []
    private var createdEvents: [EventDraft] = []

    private func model(lists: [CalendarSource] = [CalendarSource(id: "work", title: "Work", tint: .blue)]) -> SearchPaletteModel {
        let model = SearchPaletteModel(findTemporal: { [weak self] _, _, _ in
            self?.parsed += 1
            return nil
        }, parse: { [weak self] _, _, _, _, _ in
            self?.parsed += 1
            return []
        }, prepareParser: { _ in })
        model.calendar = calendar
        model.now = { [reference] in reference }
        model.timeFormat = { .twentyFourHour }
        model.commitBeat = .zero
        model.taskLists = { lists }
        model.eventCalendars = { [CalendarSource(id: "home", title: "Home", tint: .green)] }
        model.createTask = { [weak self] draft in
            self?.createdTasks.append(draft)
            return TaskItem(id: "t", title: draft.title, listID: "work")
        }
        model.createEvent = { [weak self] draft in
            self?.createdEvents.append(draft)
            return EventSnapshot(eventIdentifier: "e", calendarIdentifier: "home", calendarTitle: "Home", title: draft.title,
                                 start: draft.start, end: draft.end, isAllDay: false, location: nil, notes: nil,
                                 hasAttendees: false, isRecurring: false)
        }
        return model
    }

    func testNewTaskOpensAnEmptyTaskEditor() async {
        let model = model()
        await model.startCreating(.task)
        XCTAssertTrue(model.isRefining)
        XCTAssertEqual(model.selectedKind, .createTask)
        XCTAssertEqual(model.edit?.title, "")
    }

    func testNewTaskNeverReadsTheParser() async {
        let model = model()
        await model.startCreating(.task)
        XCTAssertEqual(parsed, 0)
    }

    func testNewEventStartsAtTheNextWholeHourForAnHour() async {
        let model = model()
        await model.startCreating(.event)
        let draft = model.eventEdit?.eventDraft(calendar: calendar)
        XCTAssertEqual(draft?.start, calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 13)))
        XCTAssertEqual(draft?.end, calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 14)))
    }

    func testAnEmptyTitleCreatesNothing() async {
        let model = model()
        await model.startCreating(.task)
        model.createFromKeyboard()
        await model.settle()
        XCTAssertTrue(createdTasks.isEmpty)
    }

    func testATypedTitleCreatesTheTaskAndClosesQuickAdd() async {
        let model = model()
        await model.startCreating(.task)
        model.edit?.title = "Buy milk"
        model.createFromKeyboard()
        await model.settle()
        XCTAssertEqual(createdTasks.map(\.title), ["Buy milk"])
        XCTAssertFalse(model.isRefining)
    }

    func testWithoutAListNewTaskOpensNothing() async {
        let model = model(lists: [])
        await model.startCreating(.task)
        XCTAssertFalse(model.isRefining)
    }

    func testQuickAddStartedEmptyIsKnownAsSuch() async {
        let model = model()
        await model.startCreating(.event)
        XCTAssertTrue(model.isCreatingWithoutQuery)
    }
}
