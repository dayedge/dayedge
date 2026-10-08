import XCTest
@testable import Shell
@testable import Domain
@testable import UI
@testable import Agenda

@MainActor
final class TaskOccurrenceActionTests: XCTestCase {
    private func makeActions(notices: NoticeCenter) -> TaskActions {
        let defaults = UserDefaults(suiteName: "TaskOccurrenceActionTests-\(UUID().uuidString)")!
        let repository = TaskRepository(
            provider: MockTaskDataProvider(),
            listVisibility: SourceVisibilityStore(kind: .taskLists, defaults: defaults),
            noticeCenter: notices, defaults: defaults
        )
        return TaskActions(repository: repository)
    }

    func testNextOccurrenceNavigatesAndMissingOneShowsTheEventNotice() {
        let notices = NoticeCenter()
        let actions = makeActions(notices: notices)
        var navigated: (String, Date, Bool)?
        actions.navigate = { navigated = ($0, $1, $2) }
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let due = calendar.startOfDay(for: now)
        let weekly = TaskItem(id: "w", title: "W", listID: "work", dueDate: due, recurrence: .weekly)

        actions.perform(.nextOccurrence, on: weekly, day: due, now: now, calendar: calendar)
        XCTAssertEqual(navigated?.0, "w")
        XCTAssertEqual(navigated?.1, calendar.date(byAdding: .day, value: 7, to: due))
        XCTAssertEqual(navigated?.2, false, "stays in the current calendar view")

        navigated = nil
        actions.perform(.previousOccurrence, on: weekly, day: due, now: now, calendar: calendar)
        XCTAssertNil(navigated)
        XCTAssertEqual(notices.currentNotice?.title, "No previous occurrence found")
    }

    func testShowInCalendarSwitchesToTheCalendarOnTheShownDay() {
        let actions = makeActions(notices: NoticeCenter())
        var navigated: (String, Date, Bool)?
        actions.navigate = { navigated = ($0, $1, $2) }
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let overdue = TaskItem(id: "o", title: "O", listID: "work", dueDate: calendar.date(byAdding: .day, value: -3, to: now))
        actions.perform(.showInCalendar, on: overdue, now: now, calendar: calendar)
        XCTAssertEqual(navigated?.1, calendar.startOfDay(for: now), "an overdue task is shown on today")
        XCTAssertEqual(navigated?.2, true)
    }

    func testScrollTargetResolvesToTheTaskRow() {
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: Date())
        let section = AgendaDaySection(date: day, events: [])
        let task = TaskItem(id: "t", title: "T", listID: "l", dueDate: day)
        let anchor = AgendaSectionProjection.anchor(
            for: AgendaScrollTarget(date: day, taskID: "t"), in: [section], nowPresentation: nil,
            tasks: { _ in DayTasks(untimed: [task]) }
        )
        XCTAssertEqual(anchor, .task(sectionID: section.id, taskID: "t"))
    }
}
