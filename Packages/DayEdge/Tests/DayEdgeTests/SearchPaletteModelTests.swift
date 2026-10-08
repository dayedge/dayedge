import CalendarIndex
import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// The palette's deterministic contract, with the real parsers. Reference:
/// Wednesday 2026-09-23 12:00, Monday-first week.
@MainActor
final class SearchPaletteModelTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }()
    private var reference: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))! }
    private let lists = [CalendarSource(id: "work", title: "Work", tint: .blue)]

    private func model() -> SearchPaletteModel {
        let model = SearchPaletteModel()
        model.calendar = calendar
        model.now = { [reference] in reference }
        model.taskLists = { [lists] in lists }
        model.commitBeat = .zero
        return model
    }

    private func resolve(_ model: SearchPaletteModel, _ query: String) async {
        model.update(query: query)
        await model.settle()
    }

    private func kinds(_ model: SearchPaletteModel) -> [PaletteAction.Kind] { model.actions.map(\.kind) }

    /// Records created drafts; returns a saved task for each.
    private func recordCreation(_ model: SearchPaletteModel, into drafts: @escaping (TaskDraft) -> Void) {
        model.createTask = { draft in
            drafts(draft)
            return TaskItem(id: "new", title: draft.title, listID: draft.listID ?? "work", dueDate: draft.dueDate)
        }
    }

    // MARK: - Events

    private let calendars = [CalendarSource(id: "cal-family", title: "Family", tint: .green)]

    private func eventModel(into drafts: @escaping (EventDraft) -> Void = { _ in },
                            created: @escaping (EventSnapshot) -> Void = { _ in }) -> SearchPaletteModel {
        let model = model()
        model.eventCalendars = { [calendars] in calendars }
        model.createEvent = { draft in
            drafts(draft)
            return EventSnapshot(eventIdentifier: "e1", calendarIdentifier: draft.calendarIdentifier ?? "cal-family",
                                 calendarTitle: "Family", title: draft.title, start: draft.start, end: draft.end,
                                 isAllDay: draft.isAllDay, location: draft.location, notes: nil,
                                 hasAttendees: false, isRecurring: false)
        }
        model.onEventCreated = created
        return model
    }

    func testEventAndTaskRowsInTheDecisionsOrder() async {
        let model = eventModel()
        await resolve(model, "lunch tomorrow 1pm at Starbucks")
        XCTAssertEqual(Array(kinds(model).prefix(2)), [.createEvent, .createTask])
        XCTAssertEqual(model.actions[0].title, "Create event “Lunch”")
        XCTAssertEqual(model.actions[0].subtitle, "Tomorrow 13:00–14:00 · Starbucks")
        XCTAssertTrue(model.actions[0].supportsRefinement, "Tab edits the event in place")
        XCTAssertEqual(model.actions[1].title, "Create task “Lunch at Starbucks”")
        XCTAssertEqual(model.selectedKind, .createEvent)

        await resolve(model, "pay rent friday")
        XCTAssertEqual(Array(kinds(model).prefix(2)), [.createTask, .createEvent], "a day alone: task first")

        await resolve(model, "dinner friday 7pm #family")
        XCTAssertEqual(model.actions[0].subtitle, "Friday 25 Sep 19:00–20:00 · Family")

        await resolve(model, "conference 3-5 oct")
        XCTAssertEqual(kinds(model).first, .createEvent)
        XCTAssertEqual(model.actions[0].subtitle, "Saturday 3 Oct – Monday 5 Oct · All day")
        XCTAssertFalse(kinds(model).contains(.createTask), "a span of days is an event only")
    }

    func testEventRowsNeedACalendarAndTaskRowsAList() async {
        let noCalendars = model()
        await resolve(noCalendars, "lunch tomorrow 1pm at Starbucks")
        XCTAssertFalse(kinds(noCalendars).contains(.createEvent))
        XCTAssertEqual(noCalendars.actions[0].title, "Create “Lunch at Starbucks”", "alone: no kind in the title")

        let noLists = eventModel()
        noLists.taskLists = { [] }
        await resolve(noLists, "lunch tomorrow 1pm")
        XCTAssertEqual(kinds(noLists).first, .createEvent)
        XCTAssertFalse(kinds(noLists).contains(.createTask))
    }

    func testCreateEventSaysWhetherItsTimeIsFree() async {
        let model = eventModel()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference))!
        let at = { (hour: Int) in self.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)! }
        model.eventsOn = { day in
            guard self.calendar.isDate(day, inSameDayAs: tomorrow) else { return [] }
            return [AgendaEventModel(startTime: "13:00", endTime: "14:00", startDate: at(13), endDate: at(14),
                                     title: "Review", myResponseStatus: .accepted),
                    AgendaEventModel(startTime: "16:00", endTime: "17:00", startDate: at(16), endDate: at(17),
                                     title: "Sync", myResponseStatus: .pending)]
        }
        await resolve(model, "lunch tomorrow 1pm")
        XCTAssertEqual(model.actions.first { $0.kind == .createEvent }?.conflict, .busy)
        await resolve(model, "call tomorrow 4pm")
        XCTAssertEqual(model.actions.first { $0.kind == .createEvent }?.conflict, .unconfirmed)
        await resolve(model, "gym tomorrow 9am")
        XCTAssertEqual(model.actions.first { $0.kind == .createEvent }?.conflict, .free)
        await resolve(model, "offsite tomorrow all day")
        XCTAssertNil(model.actions.first { $0.kind == .createEvent }?.conflict, "all day: no dot")
        XCTAssertNil(model.actions.first { $0.kind == .createTask }?.conflict)
    }

    func testTabEditsTheEventInPlaceAndShowsWhatItRunsInto() async {
        var drafts: [EventDraft] = []
        let model = eventModel(into: { drafts.append($0) })
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference))!
        let at = { (hour: Int) in self.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)! }
        let review = AgendaEventModel(startTime: "13:30", endTime: "14:30", startDate: at(13).addingTimeInterval(1800),
                                      endDate: at(14).addingTimeInterval(1800), title: "Review", myResponseStatus: .accepted)
        model.eventsOn = { day in self.calendar.isDate(day, inSameDayAs: tomorrow) ? [review] : [] }

        await resolve(model, "lunch tomorrow 1pm at Starbucks")
        XCTAssertEqual(model.selectedKind, .createEvent)
        XCTAssertTrue(model.refine())
        await model.settle()
        XCTAssertTrue(model.isRefining)
        XCTAssertEqual(model.visibleActions.map(\.kind), [.createEvent], "the alternatives step aside")
        XCTAssertEqual(model.eventEdit?.title, "Lunch")
        XCTAssertEqual(model.eventEdit?.location, "Starbucks")
        XCTAssertEqual(model.editOverlap?.event.title, "Review")
        XCTAssertEqual(model.editOverlap?.conflict, .busy)

        // Moving it to 15:00 clears the overlap; the length goes along.
        model.eventEdit?.setStart(at(15))
        await model.settle()
        XCTAssertNil(model.editOverlap)
        XCTAssertEqual(model.eventEdit?.end, at(16))

        model.eventEdit?.title = "Team lunch"
        model.executeSelected()
        await model.settle()
        XCTAssertEqual(drafts.first?.title, "Team lunch")
        XCTAssertEqual(drafts.first?.start, at(15))
        XCTAssertEqual(drafts.first?.end, at(16))
        XCTAssertEqual(drafts.first?.location, "Starbucks")
    }

    func testEscLeavesTheEventEditorKeepingWhatWasEdited() async {
        var drafts: [EventDraft] = []
        let model = eventModel(into: { drafts.append($0) })
        await resolve(model, "lunch tomorrow 1pm")
        model.refine()
        model.eventEdit?.title = "Team lunch"
        XCTAssertTrue(model.collapse())
        XCTAssertFalse(model.isRefining)
        XCTAssertEqual(Array(kinds(model).prefix(2)), [.createEvent, .createTask])
        model.refine()
        XCTAssertEqual(model.eventEdit?.title, "Team lunch", "expanding again finds the field as left")
        model.collapse()
        model.submitQuery()   // collapsed: Return creates — with the edit
        await model.settle()
        XCTAssertEqual(drafts.map(\.title), ["Team lunch"])
    }

    func testANewQueryStartsOver() async {
        let model = eventModel()
        await resolve(model, "lunch tomorrow 1pm")
        model.refine()
        model.eventEdit?.title = "Team lunch"
        model.collapse()
        await resolve(model, "dinner tomorrow 7pm")
        model.refine()
        XCTAssertEqual(model.eventEdit?.title, "Dinner")
    }

    /// Expanded, plain Return never creates; ⌘Return does, from anywhere —
    /// an open picker closes first. Same for tasks and events.
    func testExpandedOnlyCommandReturnCreates() async {
        var tasks: [TaskDraft] = []
        let taskModel = model()
        recordCreation(taskModel, into: { tasks.append($0) })
        await resolve(taskModel, "dentysta tomorrow")
        taskModel.refine()
        taskModel.submitQuery()   // Return in the query field
        await taskModel.settle()
        XCTAssertTrue(tasks.isEmpty, "Return doesn't create while expanded")
        taskModel.openChildEditor = .date
        taskModel.createFromKeyboard()
        await taskModel.settle()
        XCTAssertEqual(tasks.map(\.title), ["Dentysta"])
        XCTAssertNil(taskModel.openChildEditor, "the picker closed first")

        var events: [EventDraft] = []
        let eventModel = eventModel(into: { events.append($0) })
        await resolve(eventModel, "lunch tomorrow 1pm")
        eventModel.refine()
        eventModel.submitQuery()
        await eventModel.settle()
        XCTAssertTrue(events.isEmpty)
        eventModel.openChildEditor = .time
        eventModel.createFromKeyboard()
        eventModel.createFromKeyboard()   // a second press while saving: still one
        await eventModel.settle()
        XCTAssertEqual(events.map(\.title), ["Lunch"])
    }

    func testCollapsedReturnAndCommandReturnBothCreate() async {
        var tasks: [TaskDraft] = []
        let first = model()
        recordCreation(first, into: { tasks.append($0) })
        await resolve(first, "dentysta tomorrow")
        first.submitQuery()
        await first.settle()
        let second = model()
        recordCreation(second, into: { tasks.append($0) })
        await resolve(second, "fryzjer tomorrow")
        second.createFromKeyboard()
        await second.settle()
        XCTAssertEqual(tasks.map(\.title), ["Dentysta", "Fryzjer"])
    }

    func testAnInvalidEditCreatesNothing() async {
        var tasks: [TaskDraft] = []
        let model = model()
        recordCreation(model, into: { tasks.append($0) })
        await resolve(model, "dentysta tomorrow")
        model.refine()
        model.edit?.title = "   "
        model.createFromKeyboard()
        await model.settle()
        XCTAssertTrue(tasks.isEmpty)
    }

    func testReturnCreatesTheEventThenReportsIt() async {
        var drafts: [EventDraft] = []
        var created: [EventSnapshot] = []
        let model = eventModel(into: { drafts.append($0) }, created: { created.append($0) })
        await resolve(model, "dinner friday 7pm #family @Home")
        model.executeSelected()
        await model.settle()
        XCTAssertEqual(drafts.first?.title, "Dinner")
        XCTAssertEqual(drafts.first?.calendarIdentifier, "cal-family")
        XCTAssertEqual(drafts.first?.location, "Home")
        XCTAssertEqual(created.map(\.title), ["Dinner"])
        XCTAssertTrue(model.actions.isEmpty, "the palette clears once saved")
    }

    func testAFailedEventSaveKeepsThePalette() async {
        let model = eventModel()
        model.createEvent = { _ in throw EventEditError.notWritable }
        await resolve(model, "lunch tomorrow 1pm")
        model.executeSelected()
        await model.settle()
        XCTAssertEqual(model.selectedKind, .createEvent)
        XCTAssertFalse(model.isCommitting)
    }

    // MARK: - Precedence

    func testPureDateIsGoToDateWithPlaceholders() async {
        let model = model()
        await resolve(model, "next Friday")
        XCTAssertEqual(kinds(model), [.goToDate, .search, .askAI])
        XCTAssertEqual(model.actions[0].title, "Go to Friday 2 Oct")
        XCTAssertEqual(model.selectedKind, .goToDate)
        XCTAssertFalse(model.actions[0].supportsRefinement, "no Tab affordance on Go to Date")
    }

    func testSentenceIsCreateTaskWithItsInterpretation() async {
        let model = model()
        await resolve(model, "send invoice next Friday at 10 #work")
        XCTAssertEqual(kinds(model), [.createTask, .search, .askAI])
        XCTAssertEqual(model.actions[0].title, "Create “Send invoice”")
        XCTAssertEqual(model.actions[0].subtitle, "Friday 2 Oct 10:00 · Work")
        XCTAssertTrue(model.actions[0].supportsRefinement)
        XCTAssertEqual(model.selectedKind, .createTask)
    }

    func testEmbeddedDateIsATaskNotANavigation() async {
        let model = model()
        await resolve(model, "invoice next Friday")
        XCTAssertEqual(kinds(model), [.createTask, .search, .askAI], "the strict date parser must not match inside a sentence")
        XCTAssertEqual(model.actions[0].title, "Create “Invoice”")
        XCTAssertEqual(model.actions[0].subtitle, "Friday 2 Oct")
    }

    func testNothingRecognizedSelectsAskAndEnterAsksTheQuery() async {
        let model = model()
        var ran = false
        var asked: [String] = []
        model.onGoToDate = { _ in ran = true }
        recordCreation(model) { _ in ran = true }
        model.onAsk = { asked.append($0) }
        await resolve(model, "  meeting with John notes ")
        XCTAssertEqual(kinds(model), [.search, .askAI])
        XCTAssertTrue(model.isSearchShown, "nothing else to run: Search shows, as No matches")
        XCTAssertFalse(model.isSearchSelectable)
        XCTAssertEqual(model.selectedKind, .askAI)
        XCTAssertFalse(model.refine(), "nothing to refine on Ask")
        model.executeSelected()
        XCTAssertEqual(asked, ["meeting with John notes"])
        XCTAssertFalse(ran)
        XCTAssertEqual(kinds(model), [.search, .askAI], "the palette stays as it was, for going back")
    }

    func testNoTaskCreationWithoutWritableLists() async {
        let model = model()
        model.taskLists = { [] }
        await resolve(model, "buy milk tomorrow")
        XCTAssertEqual(kinds(model), [.search, .askAI])
    }

    // MARK: - Keyboard contract

    func testArrowsWalkTheEnabledActions() async {
        let model = model()
        await resolve(model, "buy milk tomorrow")
        model.moveSelection(1)
        XCTAssertEqual(model.selectedKind, .askAI, "Search without matches gives way to Create")
        model.moveSelection(-1)
        XCTAssertEqual(model.selectedKind, .createTask)
    }

    func testSearchIsDisabledWithoutASearchableWord() async {
        let model = model()
        await resolve(model, "?!")
        XCTAssertEqual(model.actions.first { $0.kind == .search }?.isEnabled, false)
        XCTAssertEqual(model.selectedKind, .askAI)
    }

    func testEnterRunsTheSelectedActionAndClears() async throws {
        let model = model()
        var went: SearchIntent?
        model.onGoToDate = { went = $0 }
        await resolve(model, "tomorrow")
        model.executeSelected()
        XCTAssertEqual(went, .jumpToDate(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!))
        XCTAssertTrue(model.actions.isEmpty)

        var created: TaskDraft?
        var arrived: TaskItem?
        recordCreation(model) { created = $0 }
        model.onTaskCreated = { arrived = $0 }
        await resolve(model, "buy milk tomorrow !!")
        model.executeSelected()
        await model.settle()
        let draft = try XCTUnwrap(created)
        XCTAssertEqual(arrived?.title, "Buy milk", "only a saved task moves on")
        XCTAssertTrue(model.actions.isEmpty)
        XCTAssertEqual(draft.title, "Buy milk")
        XCTAssertEqual(draft.priority, .medium)
        XCTAssertEqual(draft.dueDate, calendar.date(from: DateComponents(year: 2026, month: 9, day: 24)))
    }

    func testTabRefinesInPlaceEscCollapsesEnterCreatesTheEditedTask() async throws {
        let model = model()
        var created: TaskDraft?
        recordCreation(model) { created = $0 }
        await resolve(model, "send invoice next Friday at 10")

        XCTAssertTrue(model.refine())
        XCTAssertTrue(model.isRefining)
        XCTAssertFalse(model.refine(), "Tab doesn't expand again once expanded")
        XCTAssertEqual(model.edit?.title, "Send invoice")
        XCTAssertEqual(model.edit?.hasTime, true)

        XCTAssertTrue(model.collapse())
        XCTAssertFalse(model.isRefining)
        XCTAssertFalse(model.collapse(), "nothing left to collapse: Esc goes on to close the palette")

        model.refine()
        model.edit?.title = "Send final invoice"
        model.edit?.priority = .high
        model.edit?.listID = "work"
        model.executeSelected()
        await model.settle()
        let draft = try XCTUnwrap(created)
        XCTAssertEqual(draft.title, "Send final invoice")
        XCTAssertEqual(draft.priority, .high)
        XCTAssertEqual(draft.listID, "work")
        XCTAssertEqual(draft.dueDate, calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 10)))
        XCTAssertTrue(draft.hasDueTime)
    }

    func testEditedTaskWithoutATitleIsNotCreated() async {
        let model = model()
        var created = false
        recordCreation(model) { _ in created = true }
        await resolve(model, "buy milk tomorrow")
        model.refine()
        model.edit?.title = "  "
        model.executeSelected()
        await model.settle()
        XCTAssertFalse(created)
    }

    // MARK: - Preview line

    func testSummaryShowsOnlyWhatWasUnderstood() async {
        let model = model()
        // ("every Friday at 17" loses its time — a known parser gap, see the corpus.)
        await resolve(model, "at 17 every Friday send report #work !!!")
        XCTAssertEqual(model.actions.first?.subtitle, "Every Friday 17:00 · Work · High Priority")
        await resolve(model, "buy milk")
        XCTAssertNil(model.actions.first?.subtitle, "title only: no second line")
    }

    func testRecurrenceSummaries() {
        XCTAssertEqual(TaskRecurrenceRule(frequency: .daily).summary, "Every day")
        XCTAssertEqual(TaskRecurrenceRule(standard: .weekdays)?.summary, "Every weekday")
        XCTAssertEqual(TaskRecurrenceRule(frequency: .weekly, interval: 2).summary, "Every 2 weeks")
        XCTAssertEqual(TaskRecurrenceRule(frequency: .monthly, daysOfMonth: [1]).summary, "Every month on the 1st")
        XCTAssertEqual(TaskRecurrenceRule(frequency: .weekly).menuValue, .weekly)
        XCTAssertEqual(TaskRecurrenceRule(frequency: .monthly, daysOfMonth: [15]).menuValue, .custom("Every month on the 15th"))
    }
}

extension SearchPaletteModelTests {
    private func glyphs(_ hints: [PaletteKeyHint]) -> [String] { hints.map { "\($0.glyph) \($0.label)" } }

    func testFooterDescribesWhatTheKeysDoNow() async {
        let model = model()
        await resolve(model, "next Friday")
        XCTAssertEqual(glyphs(model.keyHints), ["↵ Go"], "no Tab hint where there's nothing to refine")

        await resolve(model, "dentysta 13 september 9:00")
        XCTAssertEqual(glyphs(model.keyHints), ["⇥ Edit", "↵ Create"])
        XCTAssertEqual(model.actions.first?.accessibilityLabel, "Create task, Dentysta")
        XCTAssertEqual(model.keyHints.last?.accessibilityLabel, "Create with Return")

        model.refine()
        XCTAssertEqual(glyphs(model.keyHints), ["esc Back", "⌘↵ Create"], "Tab is plain traversal once expanded; Return works the field")
        XCTAssertEqual(model.keyHints.last?.accessibilityLabel, "Create with Command-Return")

        await resolve(model, "meeting with John notes")
        XCTAssertEqual(glyphs(model.keyHints), ["↵ Ask"])
    }
}

extension SearchPaletteModelTests {
    func testEditingHidesTheAlternativesAndEscBringsThemBack() async {
        let model = model()
        await resolve(model, "buy milk tomorrow")
        XCTAssertEqual(model.visibleActions.map(\.kind), [.createTask, .askAI])
        model.refine()
        XCTAssertEqual(model.visibleActions.map(\.kind), [.createTask], "the chosen interpretation only")
        model.collapse()
        XCTAssertEqual(model.visibleActions.map(\.kind), [.createTask, .askAI])
    }

    func testAFailedSaveKeepsQuickAddAndItsValues() async {
        let model = model()
        var arrived = false
        model.createTask = { _ in throw TaskSourceError.saveFailed("offline") }
        model.onTaskCreated = { _ in arrived = true }
        await resolve(model, "buy milk tomorrow")
        model.refine()
        model.edit?.title = "Buy oat milk"
        model.executeSelected()
        await model.settle()
        XCTAssertFalse(arrived, "no transition without a saved task")
        XCTAssertTrue(model.isRefining)
        XCTAssertFalse(model.isCommitting)
        XCTAssertEqual(model.edit?.title, "Buy oat milk")
    }

    func testAnOpenDatePickerOwnsEscAndReturn() async {
        let model = model()
        var created = false
        recordCreation(model) { _ in created = true }
        await resolve(model, "buy milk tomorrow")
        model.refine()
        model.openChildEditor = .date
        model.executeSelected()
        await model.settle()
        XCTAssertFalse(created, "Return belongs to the picker")
        XCTAssertTrue(model.closeChildEditor(), "Esc closes the picker first…")
        XCTAssertTrue(model.isRefining, "…and leaves Quick Add open")
        XCTAssertTrue(model.collapse())
    }

    func testTabOrderWalksTheFieldsAndWraps() {
        typealias Field = QuickAddField
        XCTAssertEqual(Field.next(after: .title, hasDate: true, backward: false), .list)
        XCTAssertEqual(Field.next(after: .date, hasDate: true, backward: false), .time)
        XCTAssertEqual(Field.next(after: .recurrence, hasDate: true, backward: false), .title, "wraps")
        XCTAssertEqual(Field.next(after: .title, hasDate: true, backward: true), .recurrence, "Shift-Tab wraps back")
        XCTAssertEqual(Field.next(after: .date, hasDate: false, backward: false), .priority, "no Time without a date")
        XCTAssertEqual(Field.next(after: .priority, hasDate: false, backward: false), .title)
        XCTAssertEqual(Field.next(after: nil, hasDate: true, backward: false), .title)
    }
}

/// Search's preview results inside the palette: selectable after Search,
/// Return → details, Tab → show where it lives.
@MainActor
final class SearchPalettePreviewTests: XCTestCase {
    private func model(events: Int, tasks: [TaskItem] = []) async -> SearchPaletteModel {
        let model = SearchPaletteModel()
        model.taskLists = { [] }
        model.results.debounce = .zero
        let base = Date().addingTimeInterval(3600)
        stubEvents(model, count: events, base: base)
        model.results.tasks = { tasks }
        model.update(query: "daily")
        await model.results.settle()
        await model.settle()
        await model.results.settle()
        return model
    }

    func testArrowsWalkSearchThenItsPreviewThenAsk() async {
        let model = await model(events: 5)
        XCTAssertEqual(model.selectableItems, [.action(.search), .result("event:e0"), .result("event:e1"),
                                               .result("event:e2"), .action(.askAI)])
        XCTAssertEqual(model.selection, .action(.search))
        model.moveSelection(1)
        XCTAssertEqual(model.selection, .result("event:e0"))
        XCTAssertEqual(model.keyHints.map { "\($0.glyph) \($0.label)" }, ["↵ Details", "⇥ Show in Calendar"])
        model.moveSelection(10)
        XCTAssertEqual(model.selection, .action(.askAI))
    }

    func testReturnOpensDetailsAndTabShowsTheResult() async {
        let model = await model(events: 1)
        var shown: [String] = []
        model.onShowResult = { shown.append($0.id) }
        model.moveSelection(1)
        model.executeSelected()
        XCTAssertEqual(model.eventDetailRequest?.eventID, "e0")
        XCTAssertEqual(model.eventDetailRequest?.action, .toggle)
        model.eventDetailPresentationChanged(eventID: "e0", isShowing: true)
        XCTAssertTrue(model.dismissResultDetails())
        XCTAssertEqual(model.eventDetailRequest?.action, .dismiss)
        XCTAssertTrue(model.refine())
        XCTAssertEqual(shown, ["event:e0"])
    }

    func testTaskResultsOpenTaskDetailsAndShowInTasks() async {
        let task = TaskItem(id: "t", title: "Daily review", listID: "l", dueDate: Date().addingTimeInterval(7200))
        let model = await model(events: 0, tasks: [task])
        var opened: [String] = []
        model.onOpenTaskResult = { task, _ in opened.append(task.id) }
        model.moveSelection(1)
        XCTAssertEqual(model.keyHints.last?.label, "Show in Tasks")
        model.executeSelected()
        XCTAssertEqual(opened, ["t"])
    }

    func testSearchItselfHasNoReturnAction() async {
        let model = await model(events: 2)
        var asked = false
        model.onAsk = { _ in asked = true }
        model.executeSelected()
        XCTAssertFalse(asked)
        XCTAssertEqual(model.keyHints.map { "\($0.glyph) \($0.label)" }, ["⇥ More"])
    }

    func testTabOnSearchOpensTheViewWhereKeysWorkTheResults() async {
        let model = await model(events: 100)
        var shown: [String] = []
        model.onShowResult = { shown.append($0.id) }
        XCTAssertTrue(model.refine(), "Tab on Search")
        XCTAssertTrue(model.isResultsViewShown)
        XCTAssertEqual(model.results.selectedEntry, 0, "starts where browsing starts")
        model.moveSelection(60)
        XCTAssertEqual(model.results.selectedEntry, 60, "beyond the opening window: not loaded yet")
        XCTAssertEqual(model.keyHints.map { "\($0.glyph) \($0.label)" }, ["esc Back"], "not loaded yet: only Back")
        model.results.show(days: 58..<63)
        await model.results.settle()
        XCTAssertEqual(model.keyHints.map { "\($0.glyph) \($0.label)" }, ["↵ Details", "⇥ Show in Calendar", "esc Back"])
        model.executeSelected()
        XCTAssertEqual(model.eventDetailRequest?.eventID, "e60")
        model.refine()
        XCTAssertEqual(shown, ["event:e60"])
        XCTAssertTrue(model.closeResultsView())
        XCTAssertFalse(model.isResultsViewShown)
        XCTAssertEqual(model.selection, .action(.search), "back on the palette, query kept")
    }
}


/// When Search is listed: with results always; without, only when nothing
/// else can run (then as "No matches").
@MainActor
final class SearchVisibilityTests: XCTestCase {
    private func model(query: String, events: Int) async -> SearchPaletteModel {
        let model = SearchPaletteModel()
        model.taskLists = { [CalendarSource(id: "work", title: "Work", tint: .blue)] }
        model.results.debounce = .zero
        stubEvents(model, count: events, base: Date().addingTimeInterval(3600))
        model.update(query: query)
        await model.results.settle()
        await model.settle()
        await model.results.settle()
        return model
    }

    func testResultsShowSearchWithPreview() async {
        let model = await model(query: "buy milk tomorrow", events: 2)
        XCTAssertEqual(model.visibleActions.map(\.kind), [.createTask, .search, .askAI])
        XCTAssertTrue(model.isSearchSelectable)
        XCTAssertEqual(model.selectableItems.count, 5)
    }

    func testNoResultsWithCreateOmitsSearch() async {
        let model = await model(query: "buy milk tomorrow", events: 0)
        XCTAssertEqual(model.visibleActions.map(\.kind), [.createTask, .askAI])
    }

    func testNoResultsAndNothingElseShowsNoMatchesAndSelectsAsk() async {
        let model = await model(query: "zzz nothing", events: 0)
        XCTAssertEqual(model.visibleActions.map(\.kind), [.search, .askAI])
        XCTAssertFalse(model.isSearchSelectable)
        XCTAssertEqual(model.selection, .action(.askAI))
    }
}


/// `count` daily events from `base`, served through the session's match /
/// load-by-id path (row id n ↔ event "e<n>").
@MainActor
func stubEvents(_ model: SearchPaletteModel, count: Int, base: Date) {
    model.results.searchMatches = { _ in
        (0..<count).map { SearchMatch(id: Int64($0), start: base.addingTimeInterval(Double($0) * 86400), isAllDay: false) }
    }
    model.results.loadEvents = { ids in
        Dictionary(uniqueKeysWithValues: ids.map {
            ($0, AgendaEventModel(id: "e\($0)", startTime: "09:00", endTime: "10:00",
                                  startDate: base.addingTimeInterval(Double($0) * 86400), title: "Daily \($0)"))
        })
    }
}
