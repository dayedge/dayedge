import AppKit
import SwiftUI
import XCTest
@testable import Shell
@testable import Domain
@testable import UI
@testable import Intelligence

private let gaps = ChatTranscriptGaps(message: 14, part: 12, dayToRows: 3)

private func eventPart(_ id: String, day: Date) -> ChatContentPart {
    .event(ChatEventReference(id: id, day: day, snapshot: ChatObjectSnapshot(title: id, detail: nil)))
}

@MainActor
final class ChatTranscriptRowsTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date())

    func testAnAnswerBecomesProseDayCardsAndOneRowPerObject() {
        let answer = ChatMessage(role: .assistant, text: "x", parts: [
            .text("Here:"), eventPart("a", day: day), eventPart("b", day: day), .text("Done.")
        ])
        let rows = ChatTranscriptRows.rows(for: answer, isLatest: false, isFirst: false, gaps: gaps, calendar: .current)
        XCTAssertEqual(rows.map(\.kind), [
            .prose("Here:"), .dayHeader(ChatDayReference(day: day)), .object(eventPart("a", day: day)),
            .object(eventPart("b", day: day)), .prose("Done.")
        ])
        XCTAssertEqual(rows.map(\.topGap), [14, 12, 3, 0, 12], "message, part, card→rows, none, part")
    }

    func testIdsStayStableAsTheAnswerGrows() {
        let id = UUID()
        let short = ChatMessage(id: id, role: .assistant, text: "x", parts: [.text("Here")])
        let longer = ChatMessage(id: id, role: .assistant, text: "x", parts: [.text("Here are"), eventPart("a", day: day)])
        let first = ChatTranscriptRows.rows(for: short, isLatest: true, isFirst: false, gaps: gaps, calendar: .current)
        let second = ChatTranscriptRows.rows(for: longer, isLatest: true, isFirst: false, gaps: gaps, calendar: .current)
        XCTAssertEqual(first[0].id, second[0].id, "the paragraph keeps its identity while it streams")
        XCTAssertEqual(Set(second.map(\.id)).count, second.count)
    }

    func testPendingReceiptsAndUser() {
        let pending = ChatMessage(role: .assistant, text: "", isPending: true)
        XCTAssertEqual(ChatTranscriptRows.rows(for: pending, isLatest: true, isFirst: false, gaps: gaps, calendar: .current).map(\.kind),
                       [.pending(isLatest: true)])
        let user = ChatMessage(role: .user, text: "Hi")
        let rows = ChatTranscriptRows.rows(for: user, isLatest: false, isFirst: true, gaps: gaps, calendar: .current)
        XCTAssertEqual(rows.map(\.kind), [.user("Hi")])
        XCTAssertEqual(rows.first?.topGap, 0, "the first message has no gap above")
    }

    func testNewestMessageFirstAnswerAboveItsQuestion() {
        let messages = ["q1", "a1", "q2", "a2", "a2b", "q3"].map {
            ChatMessage(role: $0.hasPrefix("q") ? .user : .assistant, text: $0)
        }
        XCTAssertEqual(ChatTranscriptRows.newestFirst(messages).map { messages[$0].text },
                       ["q3", "a2b", "a2", "q2", "a1", "q1"])
        let rows = ChatTranscriptRowCache().rows(for: messages, gaps: gaps, calendar: .current)
        XCTAssertEqual(rows.first?.kind, .user("q3"))
        XCTAssertEqual(rows.first?.topGap, 0, "the newest message is first on screen: no gap above")
        XCTAssertEqual(rows.dropFirst().first?.topGap, 14)
    }

    func testTheCacheRebuildsOnlyWhatChanged() {
        let cache = ChatTranscriptRowCache()
        var messages = (0..<10).map { ChatMessage(role: $0 % 2 == 0 ? .user : .assistant, text: "m\($0)") }
        _ = cache.rows(for: messages, gaps: gaps, calendar: .current)
        XCTAssertEqual(cache.builds, 10)
        messages[9].text = "m9 more"
        messages[9].parts = [.text("m9 more")]
        _ = cache.rows(for: messages, gaps: gaps, calendar: .current)
        XCTAssertEqual(cache.builds, 11, "only the streaming message")
        messages.append(ChatMessage(role: .user, text: "next"))
        _ = cache.rows(for: messages, gaps: gaps, calendar: .current)
        XCTAssertEqual(cache.builds, 13, "the new one, and the one that stopped being latest and first")
    }
}

@MainActor
final class ChatScrollFollowTests: XCTestCase {
    private func metrics(offset: CGFloat, content: CGFloat = 2500, viewport: CGFloat = 500) -> ScrollMetrics {
        ScrollMetrics(offset: offset, contentHeight: content, viewportHeight: viewport)
    }

    func testTheJumpButtonShowsOnlyWellBelowTheTop() {
        let follow = ChatScrollFollow()
        follow.observe(metrics(offset: 0))
        XCTAssertFalse(follow.showsJump)
        follow.observe(metrics(offset: 200))
        XCTAssertFalse(follow.showsJump, "a little down: not yet")
        follow.observe(metrics(offset: 500))
        XCTAssertTrue(follow.showsJump, "more than ¾ of a viewport down")
        follow.observe(metrics(offset: 250))
        XCTAssertTrue(follow.showsJump, "stays until clearly back")
        follow.observe(metrics(offset: 100))
        XCTAssertFalse(follow.showsJump)
    }

    func testJumpHidesAndAsksForAScroll() {
        let follow = ChatScrollFollow()
        follow.observe(metrics(offset: 900))
        XCTAssertTrue(follow.showsJump)
        follow.jumpToLatest()
        XCTAssertFalse(follow.showsJump)
        XCTAssertEqual(follow.jumpRequests, 1)
    }
}

/// The transcript stays lazy and settles: a long conversation builds only
/// the rows near the top (the newest), and streaming into it stays fast.
@MainActor
final class ChatTranscriptStressTests: XCTestCase {
    func testALongConversationBuildsOnlyVisibleRowsAndStreamsFast() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let repository = TaskRepository(provider: MockTaskDataProvider(),
                                        listVisibility: SourceVisibilityStore(kind: .taskLists, defaults: defaults),
                                        noticeCenter: NoticeCenter(), defaults: defaults)
        let actions = TaskActions(repository: repository)
        let calendar = Calendar.current
        var events: [String: AgendaEventModel] = [:]
        var lookedUp = Set<String>()
        var messages: [ChatMessage] = []
        for turn in 0..<75 {
            messages.append(ChatMessage(role: .user, text: "Question \(turn)"))
            var parts: [ChatContentPart] = [.text("Here is what you had — a paragraph of prose to wrap over a couple of lines.")]
            for dayOffset in 0..<6 {
                let day = calendar.startOfDay(for: Date()).addingTimeInterval(Double(turn * 7 + dayOffset) * -86400)
                for n in 0..<4 {
                    let event = AgendaEventModel(id: "t\(turn)-d\(dayOffset)-\(n)", startTime: "10:30", endTime: "10:55",
                                                 startDate: day.addingTimeInterval(37800), endDate: day.addingTimeInterval(39300),
                                                 title: "FW: 1F - refinement - Nurt 2 \(n)", subtitle: "Microsoft Teams",
                                                 videoService: .teams, isRecurring: n == 0, calendarName: "Calendar",
                                                 videoURL: "https://teams.microsoft.com/x")
                    events[event.id] = event
                    parts.append(.event(ChatEventReference(id: event.id, day: day, snapshot: ChatObjectSnapshot(title: event.title, detail: nil))))
                }
            }
            messages.append(ChatMessage(role: .assistant, text: "x", parts: parts))
        }
        let totalObjects = events.count  // 1,800
        let objects = ChatObjectContext(event: { id, _ in lookedUp.insert(id); return events[id] }, taskActions: actions,
                                        taskCoordinator: CalendarTaskCoordinator(actions: actions))
        let follow = ChatScrollFollow()
        func view(_ messages: [ChatMessage]) -> some View {
            ChatTranscriptView(messages: messages, objects: objects, approvals: ChatApprovals(), follow: follow)
                .frame(width: 400, height: 600)
        }
        let host = NSHostingView(rootView: AnyView(view(messages)))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertLessThan(lookedUp.count, totalObjects / 10, "only rows near the top are built (\(lookedUp.count) of \(totalObjects))")

        // Settles: more layout passes without changes do no new work.
        let settled = lookedUp.count
        for _ in 0..<5 { host.layoutSubtreeIfNeeded() }
        XCTAssertEqual(lookedUp.count, settled)

        // Streaming a new answer into the long conversation stays fast.
        messages.append(ChatMessage(role: .user, text: "One more"))
        let answerID = UUID()
        var slowest: TimeInterval = 0
        for step in 1...60 {
            var streaming = messages
            streaming.append(ChatMessage(id: answerID, role: .assistant, text: "x",
                                         parts: [.text(String(repeating: "word ", count: step * 4))]))
            let start = Date()
            host.rootView = AnyView(view(streaming))
            host.layoutSubtreeIfNeeded()
            slowest = max(slowest, Date().timeIntervalSince(start))
            try await Task.sleep(for: .milliseconds(5))
        }
        print("TRANSCRIPT built \(lookedUp.count) of \(totalObjects) event rows; slowest streamed update \(Int(slowest * 1000)) ms")
        XCTAssertLessThan(slowest, 0.25, "each streamed update lays out quickly (slowest \(slowest)s)")
        XCTAssertLessThan(lookedUp.count, totalObjects / 10, "streaming didn't build the history")
    }
}
