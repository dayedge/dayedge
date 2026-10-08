import Foundation
import Domain

/// What the assistant's tools may read — the one seam between them and the
/// app's data, so tools stay testable with plain values.
package protocol AssistantDataSource: Sendable {
    /// Visible events, grouped by day (days without events may be absent).
    func agenda(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection]
    /// Open tasks and recently completed ones, from lists not excluded in
    /// Settings.
    func taskSnapshot() async -> AssistantTaskSnapshot
    /// Public holidays in the user's holiday region (Settings → Calendars),
    /// by day key (`WorkdayCalculator.dateKey`). Empty when there's no
    /// region or they can't be loaded.
    func holidays(in range: DateInterval, calendar: Calendar) async -> AssistantHolidays
    /// Events matching a search — the same query the search field runs
    /// (words, `subject`, `from`, `with`, dates) over the whole index. The
    /// `limit` nearest to now are returned (upcoming soonest, then the most
    /// recent past), in date order, with how many matched in all.
    func searchEvents(_ query: SearchQueryParts, limit: Int, now: Date, calendar: Calendar) async -> AssistantEventSearch
}

/// Events found by a search: the nearest few, and the full count.
package struct AssistantEventSearch {
    package var total: Int
    /// In date order, each with the day it's on.
    package var items: [(event: AgendaEventModel, day: Date)]

    /// The `limit` nearest to today — from today on soonest first, then the
    /// most recent before — returned in date order.
    package static func nearest<T>(_ items: [T], start: (T) -> Date, limit: Int, now: Date, calendar: Calendar) -> [T] {
        let today = calendar.startOfDay(for: now)
        let upcoming = items.filter { start($0) >= today }.sorted { start($0) < start($1) }
        let past = items.filter { start($0) < today }.sorted { start($0) > start($1) }
        return Array((upcoming + past).prefix(limit)).sorted { start($0) < start($1) }
    }

    /// The search's rules over one loaded event — for sources without an
    /// index (tests): words anywhere, subject in the title, from the
    /// organizer (`me`: none recorded), with among the attendees.
    package static func matches(_ event: AgendaEventModel, _ query: SearchQueryParts) -> Bool {
        func has(_ words: String?, in fields: [String?]) -> Bool {
            let needles = TaskSearch.words(in: words ?? "")
            let haystack = fields.compactMap { $0 }.joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return needles.allSatisfy { haystack.contains($0) }
        }
        let people = event.attendees.map(\.name)
        return has(query.text, in: [event.title, event.subtitle, event.notes, event.calendarName, event.organizerName] + people)
            && has(query.subject, in: [event.title])
            && has(query.organizer, in: [event.organizerName])
            && has(query.attendee, in: people)
            && (!query.organizedByMe || event.organizerName == nil)
    }
}

extension AssistantDataSource {
    /// Without an index: the agenda within a year either side of now (or
    /// the query's range inside that), matched in memory.
    package func searchEvents(_ query: SearchQueryParts, limit: Int, now: Date, calendar: Calendar) async -> AssistantEventSearch {
        let year: TimeInterval = 366 * 86400
        let bounds = DateInterval(start: now.addingTimeInterval(-year), end: now.addingTimeInterval(year))
        guard let range = query.interval.map({ $0.intersection(with: bounds) }) ?? bounds else {
            return AssistantEventSearch(total: 0, items: [])
        }
        let found = await agenda(in: range, calendar: calendar)
            .filter { range.contains($0.date) && $0.date < range.end }
            .flatMap { section in section.events.map { (event: $0, day: section.date) } }
            .filter { AssistantEventSearch.matches($0.event, query) }
        return AssistantEventSearch(total: found.count,
                                    items: AssistantEventSearch.nearest(found, start: \.day, limit: limit, now: now, calendar: calendar))
    }
}

package struct AssistantHolidays: Equatable, Sendable {
    /// ISO 3166-1 region the holidays are for; nil when none is set.
    package var region: String?
    package var namesByDayKey: [String: String] = [:]
    /// Weekend weekdays for the region (1 = Sunday).
    package var weekendWeekdays: Set<Int> = [1, 7]

    package func name(for day: Date, calendar: Calendar) -> String? {
        namesByDayKey[WorkdayCalculator.dateKey(for: day, calendar: calendar)]
    }

    package func isWeekend(_ day: Date, calendar: Calendar) -> Bool {
        weekendWeekdays.contains(calendar.component(.weekday, from: day))
    }
}

package struct AssistantTaskSnapshot {
    package var tasks: [TaskItem]
    package var lists: [CalendarSource]

    package func listName(for task: TaskItem) -> String? {
        lists.first { $0.id == task.listID }?.title
    }
}

/// The app's data: the same calendar provider and task repository the
/// popover reads, read on the main actor where they live.
@MainActor
package final class AppAssistantDataSource: AssistantDataSource {
    private let calendarData: CalendarDataProviding
    private let tasks: TaskRepository
    /// The same cached source the month grid's holiday marks use.
    private let holidaySource: HolidayProviding

    package init(calendarData: CalendarDataProviding, tasks: TaskRepository, holidays: HolidayProviding) {
        self.calendarData = calendarData
        self.tasks = tasks
        self.holidaySource = holidays
    }

    package func agenda(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
        await calendarData.agendaSections(in: range, calendar: calendar)
    }

    package func taskSnapshot() async -> AssistantTaskSnapshot {
        await tasks.loadIfNeeded()
        return AssistantTaskSnapshot(tasks: tasks.tasks, lists: tasks.lists)
    }

    /// On the index: every match's id and start (light), then only the
    /// nearest `limit` loaded as events.
    package func searchEvents(_ query: SearchQueryParts, limit: Int, now: Date, calendar: Calendar) async -> AssistantEventSearch {
        let matches = await calendarData.searchEventMatches(query)
        let nearest = AssistantEventSearch.nearest(matches, start: \.start, limit: limit, now: now, calendar: calendar)
        let events = await calendarData.searchEvents(ids: nearest.map(\.id))
        let items = nearest.compactMap { match in events[match.id].map { (event: $0, day: calendar.startOfDay(for: match.start)) } }
        return AssistantEventSearch(total: matches.count, items: items)
    }

    package func holidays(in range: DateInterval, calendar: Calendar) async -> AssistantHolidays {
        let configuration = WorkdaySettings.configuration()
        var result = AssistantHolidays(region: configuration.regionCode, weekendWeekdays: configuration.weekendWeekdays)
        guard let region = configuration.regionCode else { return result }
        let firstYear = calendar.component(.year, from: range.start)
        let lastYear = calendar.component(.year, from: range.end.addingTimeInterval(-1))
        for year in firstYear...max(firstYear, lastYear) {
            let holidays = (try? await holidaySource.holidays(region: region, year: year)) ?? []
            for holiday in holidays { result.namesByDayKey[holiday.dateKey] = holiday.name }
        }
        return result
    }
}
