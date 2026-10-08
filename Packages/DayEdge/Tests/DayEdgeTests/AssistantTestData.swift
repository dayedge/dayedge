import SwiftUI
@testable import Shell
@testable import Domain
@testable import Intelligence

/// A fixed week for the assistant's tools: "now" is Wednesday
/// 23 September 2026 12:00 UTC, Monday-first weeks.
enum AssistantTestData {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    static let now = date(23, 12)

    static func event(_ title: String, day: Int, from start: (Int, Int)? = nil, to end: (Int, Int)? = nil,
                      calendarName: String = "Work", place: String? = nil, attendees: [String] = [],
                      status: EventStatus = .confirmed, created: Date? = nil, modified: Date? = nil,
                      recurring: Bool = false) -> AgendaEventModel {
        AgendaEventModel(
            id: "\(title)-\(day)",
            startTime: start.map { String(format: "%02d:%02d", $0.0, $0.1) },
            endTime: end.map { String(format: "%02d:%02d", $0.0, $0.1) },
            startDate: start.map { date(day, $0.0, $0.1) },
            endDate: end.map { date(day, $0.0, $0.1) },
            title: title, subtitle: place, status: status, isRecurring: recurring, calendarName: calendarName,
            attendees: attendees.map { EventAttendee(name: $0, status: .accepted) },
            createdAt: created, modifiedAt: modified
        )
    }

    static let lists = [
        CalendarSource(id: "work", title: "Work", tint: .blue),
        CalendarSource(id: "home", title: "Home", tint: .green)
    ]

    /// Parses only "next friday" (→ Friday 25 September); everything else is
    /// free text. Keeps tests independent of the real parsers.
    static func context(events: [Int: [AgendaEventModel]] = [:], tasks: [TaskItem] = [],
                        holidays: [String: String] = [:]) -> AssistantToolContext {
        AssistantToolContext(
            data: FakeAssistantData(events: events, snapshot: AssistantTaskSnapshot(tasks: tasks, lists: lists),
                                    holidays: AssistantHolidays(region: "PL", namesByDayKey: holidays)),
            calendar: calendar,
            now: { now },
            parseDate: { text, _, _ in
                text.lowercased() == "next friday" ? .jumpToDate(date(25)) : .freeTextSearch(text)
            }
        )
    }
}

/// Events by September day; tasks as given.
struct FakeAssistantData: AssistantDataSource, @unchecked Sendable {
    let events: [Int: [AgendaEventModel]]
    let snapshot: AssistantTaskSnapshot
    var holidays = AssistantHolidays(region: "PL")

    func agenda(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
        events.keys.sorted().compactMap { day in
            let date = AssistantTestData.date(day)
            guard date >= calendar.startOfDay(for: range.start), date < range.end else { return nil }
            return AgendaDaySection(date: date, events: events[day] ?? [])
        }
    }

    func taskSnapshot() async -> AssistantTaskSnapshot { snapshot }

    func holidays(in range: DateInterval, calendar: Calendar) async -> AssistantHolidays { holidays }
}
