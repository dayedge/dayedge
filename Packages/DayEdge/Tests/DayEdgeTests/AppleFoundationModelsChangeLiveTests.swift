import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// Does Apple's on-device model call the change tools reliably? Everyday
/// requests against a small fake calendar; every card is recorded and
/// declined (nothing is written). Prints a table and fails a kind of change
/// that's right less than 80% of the time — that tool shouldn't be offered
/// to the on-device model. Event changes failed this (about half right, 2
/// runs, 1 Oct 2026), so the on-device model gets task changes only; the
/// event cases check it then makes no event change at all.
/// Opt-in: `DAYEDGE_LIVE_APPLE_MODEL=1`.
@MainActor
final class AppleFoundationModelsChangeLiveTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["DAYEDGE_LIVE_APPLE_MODEL"] == "1" else {
            throw XCTSkip("Set DAYEDGE_LIVE_APPLE_MODEL=1 to run the on-device model")
        }
        guard AssistantBackendResolver.appleOnDeviceAvailable else {
            throw XCTSkip("Apple's on-device model isn't available on this Mac")
        }
    }

    private struct Case {
        let prompt: String
        let kind: ChangeKind
        /// The card's subject should contain this.
        let subject: String
    }

    private let cases: [Case] = [
        Case(prompt: "Add a task to buy milk tomorrow", kind: .createTask, subject: "milk"),
        Case(prompt: "Remind me to call mom on Friday at 10", kind: .createTask, subject: "mom"),
        Case(prompt: "Create a task: pay rent", kind: .createTask, subject: "rent"),
        Case(prompt: "Mark Faktura as done", kind: .completeTask, subject: "Faktura"),
        Case(prompt: "I've finished Faktura, tick it off", kind: .completeTask, subject: "Faktura"),
        Case(prompt: "Change the due date of Faktura to next Monday", kind: .updateTask, subject: "Faktura"),
        Case(prompt: "Delete the task Faktura", kind: .deleteTask, subject: "Faktura"),
        Case(prompt: "Move Standup to 15:00", kind: .updateEvent, subject: "Standup"),
        Case(prompt: "Rename the Dentist event to Dentist checkup", kind: .updateEvent, subject: "Dentist"),
        Case(prompt: "Delete the Standup event", kind: .deleteEvent, subject: "Standup"),
        Case(prompt: "Schedule lunch with Anna tomorrow at 12:30", kind: .createEvent, subject: "unch"),
        Case(prompt: "Create an event Gym on Saturday at 8am", kind: .createEvent, subject: "Gym")
    ]

    func testTheOnDeviceModelCallsTheRightChangeTool() async throws {
        #if HAS_MACOS26_SDK
        guard #available(macOS 26, *) else { return }
        var correctByKind: [ChangeKind: (right: Int, total: Int)] = [:]
        var table: [String] = []

        for testCase in cases {
            let approvals = ChatApprovals()
            var context = AssistantToolContext(data: SmallCalendar())
            context.showsReferences = false
            context.offersAlwaysAllow = false
            context.isCompact = true // as AssistantBackendResolver configures it
            context.approvals = approvals
            context.changes = FakeChangeWriter()
            let backend = AppleFoundationModelsBackend(
                tools: AssistantToolbox.readOnly(context) + AssistantToolbox.changes(context),
                instructions: { AssistantInstructions.onDevice(now: $0) }
            )
            let chat = ChatSession(responder: backend, references: context.references, approvals: approvals)

            var cards: [ChangeProposal] = []
            let watcher = Task { @MainActor in
                while !Task.isCancelled {
                    if let card = approvals.pending {
                        cards.append(card)
                        approvals.decide(.deny)
                    }
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            chat.start(with: testCase.prompt)
            await chat.settle()
            watcher.cancel()

            let first = cards.first
            let offered = AssistantToolbox.changes(context).contains { $0.name.hasSuffix(testCase.kind.isEvent ? "_event" : "_task") }
            let right = offered
                ? first?.kind == testCase.kind && first?.subject.title.localizedCaseInsensitiveContains(testCase.subject) == true
                : !cards.contains { $0.kind.isEvent }
            let tally = correctByKind[testCase.kind] ?? (0, 0)
            correctByKind[testCase.kind] = (tally.right + (right ? 1 : 0), tally.total + 1)
            let reply = (chat.messages.last?.text ?? "").replacingOccurrences(of: "\n", with: " ").prefix(80)
            table.append("\(right ? "✓" : "✗") \(testCase.prompt) → \(first.map { "\($0.kind.rawValue) “\($0.subject.title)”" } ?? "no card") | \(reply)")
        }

        let report = table.joined(separator: "\n")
        FileHandle.standardError.write(Data("\n[on-device change tools]\n\(report)\n".utf8))
        for (kind, tally) in correctByKind {
            XCTAssertGreaterThanOrEqual(Double(tally.right) / Double(tally.total), 0.8,
                                        "\(kind.rawValue): \(tally.right)/\(tally.total)\n\(report)")
        }
        #endif
    }
}

private extension ChangeKind {
    var isEvent: Bool { self == .createEvent || self == .updateEvent || self == .deleteEvent }
}

/// Standup today 10:30, Dentist tomorrow 08:00 (both the user's own);
/// one task, Faktura, due today.
private struct SmallCalendar: AssistantDataSource {
    func agenda(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let days: [(Date, AgendaEventModel)] = [
            (today, event("Standup", on: today, hour: 10, minute: 30, minutes: 30, calendar: calendar)),
            (tomorrow, event("Dentist", on: tomorrow, hour: 8, minute: 0, minutes: 60, calendar: calendar))
        ]
        return days.filter { range.contains($0.0) }.map {
            AgendaDaySection(date: $0.0, events: [$0.1])
        }
    }

    private func event(_ title: String, on day: Date, hour: Int, minute: Int, minutes: Int, calendar: Calendar) -> AgendaEventModel {
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        let end = start.addingTimeInterval(Double(minutes) * 60)
        return AgendaEventModel(
            id: "\(title)-\(day.timeIntervalSince1970)",
            startTime: String(format: "%02d:%02d", hour, minute), endTime: "",
            startDate: start, endDate: end, title: title, calendarName: "Personal",
            editReference: EventEditReference(eventIdentifier: title, calendarIdentifier: "personal",
                                              occurrenceStart: start, occurrenceEnd: end, isWritable: true,
                                              invitationFrom: nil, isInvitation: false)
        )
    }

    func taskSnapshot() async -> AssistantTaskSnapshot {
        AssistantTaskSnapshot(
            tasks: [TaskItem(id: "faktura", title: "Faktura", listID: "home", dueDate: Calendar.current.startOfDay(for: Date()))],
            lists: [CalendarSource(id: "home", title: "Home", tint: .green)]
        )
    }

    func holidays(in range: DateInterval, calendar: Calendar) async -> AssistantHolidays { AssistantHolidays() }
}
