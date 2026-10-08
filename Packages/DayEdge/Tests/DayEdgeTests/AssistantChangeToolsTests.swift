import SwiftUI
import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// The change tools end to end, with a fake writer: nothing is written
/// without an approval, the card shows what will happen, Undo puts it back.
@MainActor
final class AssistantChangeToolsTests: XCTestCase {
    private typealias T = AssistantTestData

    private var writer: FakeChangeWriter!
    private var approvals: ChatApprovals!
    private var receipts: [ChatChangeReceipt] = []

    override func setUp() async throws {
        writer = FakeChangeWriter()
        approvals = ChatApprovals()
        receipts = []
        approvals.onReceipt = { [unowned self] in receipts.append($0) }
        approvals.onReceiptChange = { [unowned self] changed in
            if let index = receipts.firstIndex(where: { $0.id == changed.id }) { receipts[index] = changed }
        }
    }

    private func context(events: [Int: [AgendaEventModel]] = [:], tasks: [TaskItem] = [], remote: Bool = true) -> AssistantToolContext {
        var context = T.context(events: events, tasks: tasks)
        context.approvals = approvals
        context.changes = writer
        context.offersAlwaysAllow = remote
        return context
    }

    private func tool(_ name: String, _ context: AssistantToolContext) -> AssistantTool {
        AssistantToolbox.changes(context).first { $0.name == name }!
    }

    /// Calls the tool, answers its card (if one appears) with `decision`.
    private func call(_ tool: AssistantTool, _ arguments: [String: JSONValue],
                      deciding decision: ApprovalDecision = .allow) async throws -> (output: String, card: ChangeProposal?) {
        let finished = Flag()
        let run = Task { () throws -> String in
            defer { finished.isSet = true }
            return try await tool.call(AssistantToolArguments(arguments))
        }
        var card: ChangeProposal?
        for _ in 0..<400 {
            if let pending = approvals.pending { card = pending; break }
            if finished.isSet { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        if card != nil { approvals.decide(decision) }
        return (try await run.value, card)
    }

    private func task(_ id: String, list: String = "home", due: Date? = nil, done: Bool = false) -> TaskItem {
        TaskItem(id: id, title: id, listID: list, dueDate: due, isCompleted: done)
    }

    private func ownEvent(_ title: String, day: Int, from: (Int, Int), to: (Int, Int), recurring: Bool = false,
                          invitationFrom: String? = nil, attendees: [String] = []) -> AgendaEventModel {
        AgendaEventModel(
            id: "\(title)-\(day)", startTime: "x", endTime: "y",
            startDate: T.date(day, from.0, from.1), endDate: T.date(day, to.0, to.1),
            title: title, isRecurring: recurring, calendarName: "Work",
            attendees: attendees.map { EventAttendee(name: $0, status: .accepted) },
            editReference: EventEditReference(
                eventIdentifier: "ek-\(title)", calendarIdentifier: "work",
                occurrenceStart: T.date(day, from.0, from.1), occurrenceEnd: T.date(day, to.0, to.1),
                isWritable: true, invitationFrom: invitationFrom, isInvitation: invitationFrom != nil,
                hasAttendees: !attendees.isEmpty
            )
        )
    }

    // MARK: - Tasks

    func testCreatingATaskShowsTheCardAndCreatesOnlyAfterAllow() async throws {
        let context = context()
        let (output, card) = try await call(tool("create_task", context),
                                            ["title": .string("Call mom"), "due": .string("tomorrow 10:00"), "list": .string("Home")])
        XCTAssertEqual(card?.kind, .createTask)
        XCTAssertEqual(card?.subject.title, "Call mom")
        XCTAssertEqual(card?.subject.detail, "Tomorrow 10:00 · Home")
        XCTAssertEqual(card?.offersAlwaysAllow, true)
        XCTAssertEqual(writer.created.first?.title, "Call mom")
        XCTAssertEqual(writer.created.first?.dueDate, T.date(24, 10))
        XCTAssertEqual(writer.created.first?.hasDueTime, true)
        XCTAssertEqual(writer.created.first?.listID, "home")
        XCTAssertTrue(output.hasPrefix("Done"), output)
        XCTAssertEqual(receipts.map(\.state), [.done])
        XCTAssertTrue(receipts[0].canUndo)

        await approvals.undo(receipts[0])
        XCTAssertEqual(writer.deletedTasks, ["new-1"], "undo deletes what was created")
        XCTAssertEqual(receipts[0].state, .undone)
        XCTAssertFalse(receipts[0].canUndo)
    }

    func testDeclinedChangesWriteNothing() async throws {
        let (output, card) = try await call(tool("create_task", context()), ["title": .string("Call mom")], deciding: .deny)
        XCTAssertNotNil(card)
        XCTAssertTrue(writer.created.isEmpty)
        XCTAssertTrue(output.contains("declined"), output)
        XCTAssertEqual(receipts.map(\.state), [.declined])
    }

    func testCancelledWhileWaitingWritesNothing() async throws {
        let (output, _) = try await call(tool("create_task", context()), ["title": .string("Call mom")], deciding: .cancelled)
        XCTAssertTrue(writer.created.isEmpty)
        XCTAssertTrue(output.hasPrefix("Cancelled"), output)
        XCTAssertTrue(receipts.isEmpty)
    }

    func testAlwaysAllowSkipsTheCardForThatKindButNeverForDeletes() async throws {
        approvals.isAlwaysAllowed = { _ in true }
        let context = context(tasks: [task("Faktura")])
        let (_, createCard) = try await call(tool("create_task", context), ["title": .string("Call mom")])
        XCTAssertNil(createCard, "always allowed")
        XCTAssertEqual(writer.created.count, 1)

        let (_, deleteCard) = try await call(tool("delete_task", context), ["task": .string("Faktura")])
        XCTAssertNotNil(deleteCard, "deleting always asks")
        XCTAssertEqual(deleteCard?.offersAlwaysAllow, false)
    }

    func testOnDeviceNeverSkipsTheCard() async throws {
        approvals.isAlwaysAllowed = { _ in true }
        let (_, card) = try await call(tool("create_task", context(remote: false)), ["title": .string("Call mom")])
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.offersAlwaysAllow, false)
    }

    func testChoosingAlwaysAllowIsRemembered() async throws {
        var remembered: [ChangeKind] = []
        approvals.rememberAlwaysAllowed = { remembered.append($0) }
        _ = try await call(tool("create_task", context()), ["title": .string("Call mom")], deciding: .alwaysAllow)
        XCTAssertEqual(remembered, [.createTask])
        XCTAssertEqual(writer.created.count, 1)
    }

    func testCompletingByReferenceAndByTitle() async throws {
        let faktura = task("Faktura", due: T.date(23))
        let context = context(tasks: [faktura, task("Faktura VAT")])
        _ = context.taskLine(faktura, day: nil, list: "Home") // mints T1

        let (output, card) = try await call(tool("complete_task", context), ["task": .string("T1")])
        XCTAssertEqual(card?.subject.title, "Faktura")
        XCTAssertEqual(writer.taskChanges.map(\.id), ["Faktura"])
        XCTAssertTrue(output.contains("marked done"), output)

        let exact = try await call(tool("complete_task", context), ["task": .string("faktura")])
        XCTAssertEqual(exact.card?.subject.title, "Faktura", "an exact title wins over a longer one")
    }

    func testAmbiguousTitlesAreAskedBackWithoutACard() async throws {
        let context = context(tasks: [task("Faktura styczeń"), task("Faktura luty")])
        let (output, card) = try await call(tool("complete_task", context), ["task": .string("faktura")])
        XCTAssertNil(card)
        XCTAssertTrue(output.contains("Several tasks match"), output)
        XCTAssertTrue(writer.taskChanges.isEmpty)
    }

    func testUpdatingATaskShowsBeforeAndAfterAndUndoRestoresIt() async throws {
        let context = context(tasks: [task("Faktura", due: T.date(23))])
        let (_, card) = try await call(tool("update_task", context), ["task": .string("Faktura"), "due": .string("next friday")])
        XCTAssertEqual(card?.fields, [ChangeField(label: "Due", before: "Today", after: "Fri 25 Sep")])
        await approvals.undo(receipts[0])
        guard case .due(let date, _)? = writer.taskChanges.last?.change else { return XCTFail("expected the due date put back") }
        XCTAssertEqual(date, T.date(23))
    }

    func testAFailedTaskWriteIsAFailedReceiptWithoutUndo() async throws {
        writer.failingTaskChange = 0
        let context = context(tasks: [task("Faktura")])
        let (output, _) = try await call(tool("complete_task", context), ["task": .string("Faktura")])
        guard case .failed? = receipts.first?.state else { return XCTFail("expected a failed receipt, got \(receipts)") }
        XCTAssertFalse(receipts[0].canUndo)
        XCTAssertTrue(output.contains("Nothing was changed"), output)
    }

    func testAPartlyFailedTaskUpdatePutsBackWhatWasSaved() async throws {
        writer.failingTaskChange = 1   // the second field
        let context = context(tasks: [task("Faktura", due: T.date(23))])
        _ = try await call(tool("update_task", context), ["task": .string("Faktura"), "due": .string("next friday"),
                                                           "title": .string("Invoice")])
        guard case .failed? = receipts.first?.state else { return XCTFail("expected a failed receipt, got \(receipts)") }
        // Saved the first field, failed the second, then put the first back.
        XCTAssertEqual(writer.taskChanges.count, 2, "\(writer.taskChanges)")
        let (first, revert) = (writer.taskChanges[0].change, writer.taskChanges[1].change)
        XCTAssertEqual(String(describing: revert), String(describing: Self.reverse(of: first)))
    }

    /// The change that undoes `change` for the Faktura task above.
    private static func reverse(of change: TaskChange) -> TaskChange {
        switch change {
        case .title: .title("Faktura")
        case .due: .due(T.date(23), hasTime: false)
        default: change
        }
    }

    // MARK: - Events

    func testMovingAnEventToATimeKeepsItsDayAndLength() async throws {
        let standup = ownEvent("Standup", day: 23, from: (10, 30), to: (11, 0))
        let context = context(events: [23: [standup]])
        let (_, card) = try await call(tool("update_event", context), ["event": .string("Standup"), "start": .string("15:00")])
        XCTAssertEqual(card?.title, "Move event")
        XCTAssertEqual(card?.fields.first?.before, "Today 10:30–11:00")
        XCTAssertEqual(card?.fields.first?.after, "Today 15:00–15:30")
        XCTAssertEqual(writer.eventUpdates.first?.change.start, T.date(23, 15))
        XCTAssertTrue(receipts[0].canUndo)
    }

    func testInvitationsCantBeChangedAndDeletingOneWarns() async throws {
        let review = ownEvent("Review", day: 23, from: (14, 0), to: (15, 0), invitationFrom: "Anna", attendees: ["Anna"])
        let context = context(events: [23: [review]])
        let (output, card) = try await call(tool("update_event", context), ["event": .string("Review"), "start": .string("16:00")])
        XCTAssertNil(card)
        XCTAssertTrue(output.contains("invitation from Anna"), output)
        XCTAssertTrue(writer.eventUpdates.isEmpty)

        let (_, deleteCard) = try await call(tool("delete_event", context), ["event": .string("Review")])
        XCTAssertEqual(deleteCard?.notes.first, "Anna won't be notified. To decline, respond in Apple Calendar.")
        XCTAssertFalse(receipts.last?.canUndo ?? true, "an invitation can't be put back")
    }

    func testDeletingARepeatingEventSaysSoAndHasNoUndo() async throws {
        let daily = ownEvent("Daily", day: 23, from: (9, 0), to: (9, 15), recurring: true)
        let (_, card) = try await call(tool("delete_event", context(events: [23: [daily]])), ["event": .string("Daily")])
        XCTAssertEqual(card?.kind.isDestructive, true)
        XCTAssertEqual(card?.notes, ["Only this occurrence.", "This can't be undone."])
        XCTAssertEqual(writer.eventDeletes.count, 1)
        XCTAssertFalse(receipts[0].canUndo)
    }

    func testCreatingAnEventUsesTheDefaultCalendarAndAnHour() async throws {
        let (_, card) = try await call(tool("create_event", context()), ["title": .string("Lunch"), "start": .string("tomorrow 12:30")])
        XCTAssertEqual(card?.subject.detail, "Tomorrow 12:30–13:30 · Personal")
        XCTAssertEqual(writer.eventCreates.first?.calendarIdentifier, "personal")
        XCTAssertEqual(writer.eventCreates.first?.end, T.date(24, 13, 30))
    }

    // MARK: - Times

    func testMoments() async throws {
        let context = T.context()
        func moment(_ text: String, on day: Date? = nil) async throws -> AssistantMoment {
            try await AssistantMoment.resolve(text, on: day, context: context)
        }
        let tomorrow = try await moment("tomorrow 15:00")
        let meridiem = try await moment("tomorrow at 3pm")
        let iso = try await moment("2026-10-02T09:30")
        let dayOnly = try await moment("tomorrow")
        let timeOnDay = try await moment("9.30", on: T.date(25))
        XCTAssertEqual(tomorrow, AssistantMoment(date: T.date(24, 15), hasTime: true))
        XCTAssertEqual(meridiem, AssistantMoment(date: T.date(24, 15), hasTime: true))
        XCTAssertEqual(iso, AssistantMoment(date: T.date(2, 9, 30, month: 10), hasTime: true))
        XCTAssertEqual(dayOnly, AssistantMoment(date: T.date(24), hasTime: false))
        XCTAssertEqual(timeOnDay, AssistantMoment(date: T.date(25, 9, 30), hasTime: true))
        do {
            _ = try await AssistantMoment.resolve("15:00", context: context)
            XCTFail("a time alone needs a day")
        } catch is AssistantMoment.NeedsDay {}
        XCTAssertNil(AssistantMoment.clock("3"), "a bare number isn't a time")
        let atTen = try await moment("tomorrow at 10")
        XCTAssertEqual(atTen, AssistantMoment(date: T.date(24, 10), hasTime: true), "…unless it follows “at”")
        XCTAssertEqual(AssistantTargetResolver.titleMatches("Dentist checkup", in: ["Dentist", "Standup"], title: \.self), ["Dentist"])
        XCTAssertNil(AssistantMoment.clock("25:00"))
    }

    // MARK: - Settings

    func testOldSettingsFilesStillLoadAndDeletesAreNeverAlwaysAllowed() throws {
        let old = #"{"activeProvider":"openRouter","providers":{"openRouter":{"apiKey":"k","modelID":"m"}}}"#
        let settings = try JSONDecoder().decode(AssistantSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.activeProvider, .openRouter)
        XCTAssertEqual(settings.alwaysAllowed, [])

        let saved = #"{"alwaysAllowed":["createTask","deleteEvent"]}"#
        XCTAssertEqual(try JSONDecoder().decode(AssistantSettings.self, from: Data(saved.utf8)).alwaysAllowed, [.createTask])
    }

    // MARK: - In the conversation

    func testReceiptsLandOnTheAnswerAndStopCancelsAWaitingCard() async throws {
        let session = ChatSession(responder: PlaceholderChatResponder(delay: .seconds(10)), approvals: approvals)
        session.start(with: "add a task")
        approvals.onReceipt(ChatChangeReceipt(kind: .createTask, text: "Created “X”", state: .done))
        XCTAssertEqual(session.messages.last?.changes.map(\.text), ["Created “X”"])

        let waiting = Task { await approvals.request(ChangeProposal(kind: .createTask, subject: .init(marker: .ring(.blue), title: "Y"))) }
        while approvals.pending == nil { try await Task.sleep(for: .milliseconds(5)) }
        session.stop()
        let decision = await waiting.value
        XCTAssertEqual(decision, .cancelled)
        XCTAssertNil(approvals.pending)
        XCTAssertEqual(session.messages.count, 2, "an answer with a receipt stays after Stop")
    }
}

private final class Flag: @unchecked Sendable {
    var isSet = false
}

/// Records every write; creates get predictable ids.
@MainActor
final class FakeChangeWriter: AssistantChangeWriter {
    var created: [TaskDraft] = []
    var taskChanges: [(id: String, change: TaskChange)] = []
    var deletedTasks: [String] = []
    var eventCreates: [EventDraft] = []
    var eventUpdates: [(target: EventEditReference, change: EventChange)] = []
    var eventDeletes: [EventEditReference] = []

    func createTask(_ draft: TaskDraft) async throws -> TaskItem {
        created.append(draft)
        return TaskItem(id: "new-\(created.count)", title: draft.title, listID: draft.listID ?? "home",
                        dueDate: draft.dueDate, hasDueTime: draft.hasDueTime)
    }

    /// Which `changeTask` call throws, counting from 0 (nil: none).
    var failingTaskChange: Int?
    private var taskChangeCalls = 0

    func changeTask(_ change: TaskChange, taskID: String) async throws {
        defer { taskChangeCalls += 1 }
        if taskChangeCalls == failingTaskChange { throw TaskSourceError.saveFailed("Disk full") }
        taskChanges.append((taskID, change))
    }
    func deleteTask(_ taskID: String) async throws { deletedTasks.append(taskID) }

    func eventCalendars() async -> [WritableCalendar] {
        [WritableCalendar(identifier: "work", title: "Work", isDefault: false),
         WritableCalendar(identifier: "personal", title: "Personal", isDefault: true)]
    }

    func createEvent(_ draft: EventDraft) async throws -> EventSnapshot {
        eventCreates.append(draft)
        return snapshot(title: draft.title, start: draft.start, end: draft.end)
    }

    func updateEvent(_ target: EventEditReference, _ change: EventChange) async throws -> (before: EventSnapshot, after: EventSnapshot) {
        eventUpdates.append((target, change))
        let before = snapshot(title: "Before", start: target.occurrenceStart, end: target.occurrenceEnd)
        let after = snapshot(title: change.title ?? "Before", start: change.start ?? target.occurrenceStart,
                             end: change.end ?? target.occurrenceEnd)
        return (before, after)
    }

    func deleteEvent(_ target: EventEditReference) async throws -> EventSnapshot {
        eventDeletes.append(target)
        return snapshot(title: "Deleted", start: target.occurrenceStart, end: target.occurrenceEnd)
    }

    private func snapshot(title: String, start: Date, end: Date) -> EventSnapshot {
        EventSnapshot(eventIdentifier: "ek-\(title)", calendarIdentifier: "work", calendarTitle: "Work", title: title,
                      start: start, end: end, isAllDay: false, location: nil, notes: nil, hasAttendees: false, isRecurring: false)
    }
}

@MainActor
final class ChatChangeNarrationTests: XCTestCase {
    func testAModelThatDoesntNarrateChangesShowsOnlyTheReceipt() async {
        let approvals = ChatApprovals()
        let responder = SilentAfterChanges(approvals: approvals)
        let chat = ChatSession(responder: responder, approvals: approvals)
        chat.start(with: "add milk")
        await chat.settle()
        XCTAssertEqual(chat.messages.last?.changes.map(\.text), ["Declined: create task “Milk”"])
        XCTAssertEqual(chat.messages.last?.parts, [], "its claim isn't shown")
        XCTAssertEqual(chat.messages.last?.text, "I've added milk!", "but it stays in the model's history")
    }

    func testCompactModelsGetTaskChangesOnly() {
        var context = AssistantTestData.context()
        context.approvals = ChatApprovals()
        context.changes = FakeChangeWriter()
        XCTAssertEqual(AssistantToolbox.changes(context).count, 7)
        context.isCompact = true
        XCTAssertEqual(AssistantToolbox.changes(context).map(\.name), ["create_task", "complete_task", "update_task", "delete_task"])
    }
}

/// Records a declined change, then claims it happened anyway.
private struct SilentAfterChanges: ChatResponding {
    let approvals: ChatApprovals
    var narratesChanges: Bool { false }

    func reply(to conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                approvals.record(ChatChangeReceipt(kind: .createTask, text: "Declined: create task “Milk”", state: .declined), undo: nil)
                continuation.yield("I've added milk!")
                continuation.finish()
            }
        }
    }
}

@MainActor
final class ChatEscapeTests: XCTestCase {
    func testEscapeDeclinesAWaitingCardFirstThenStops() async throws {
        let approvals = ChatApprovals()
        let chat = ChatSession(responder: PlaceholderChatResponder(delay: .seconds(10)), approvals: approvals)
        chat.start(with: "add milk")
        let waiting = Task { await approvals.request(ChangeProposal(kind: .createTask, subject: .init(marker: .ring(.blue), title: "Milk"))) }
        while approvals.pending == nil { try await Task.sleep(for: .milliseconds(5)) }

        chat.escape()
        let decision = await waiting.value
        XCTAssertEqual(decision, .deny, "the first Esc declines the card")
        XCTAssertTrue(chat.isResponding, "…and the answer goes on")

        chat.escape()
        XCTAssertFalse(chat.isResponding, "the next Esc stops it")
        chat.escape() // idle: nothing happens
    }
}
