import Foundation

/// Generates a visually representative month grid + agenda without touching
/// EventKit. Dot patterns are derived from weekday/position rules rather
/// than one hardcoded value per date, so the shape of the data mirrors what
/// a real provider would hand back.
package struct MockCalendarDataProvider: CalendarDataProviding {
    package init() {}

    package func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor) else { return [] }

        let firstOfMonth = monthInterval.start
        let firstWeekdayOffset = (calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -firstWeekdayOffset, to: firstOfMonth) else { return [] }

        let today = calendar.startOfDay(for: Date())
        let totalCells = 42 // 6 full weeks always visible, matches the reference layout

        return (0..<totalCells).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let isCurrentMonth = calendar.isDate(date, equalTo: monthAnchor, toGranularity: .month)
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 7 // Sunday / Saturday
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
            let dayNumber = calendar.component(.day, from: date)

            let dots = dotPattern(date: date, isCurrentMonth: isCurrentMonth, isWeekend: isWeekend, isToday: isToday, calendar: calendar)

            return DayCellModel(
                date: date,
                dayNumber: dayNumber,
                isCurrentMonth: isCurrentMonth,
                isToday: isToday,
                isSelected: isSelected,
                isWeekend: isWeekend,
                dots: dots
            )
        }
    }

    private func dotPattern(date: Date, isCurrentMonth: Bool, isWeekend: Bool, isToday: Bool, calendar: Calendar) -> [DotStyle] {
        if isToday {
            return [DotStyle(tint: .mockAccent)]
        }
        // Day right after "today" gets a single lingering blue marker,
        // mirroring a day with one upcoming tracked event.
        if let today = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())),
           calendar.isDate(date, inSameDayAs: today) {
            return [DotStyle(tint: .mockAccent)]
        }
        if isWeekend {
            return []
        }
        let count = isCurrentMonth ? 5 : 4
        return Array(repeating: DotStyle(tint: .placeholder), count: count)
    }

    package func events(for date: Date, calendar: Calendar) -> [AgendaEventModel] {
        allSections(calendar: calendar).first { calendar.isDate($0.date, inSameDayAs: date) }?.events ?? []
    }

    /// Mock data is a fixed, hand-authored set of sections — `range` just
    /// filters it, unlike the real EventKit provider which actually fetches.
    /// No genuine suspension happens here; `async` only to conform to the
    /// shared range-based contract.
    package func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
        allSections(calendar: calendar).filter { range.contains($0.date) }
    }

    private func allSections(calendar: Calendar) -> [AgendaDaySection] {
        func section(_ day: Int, _ events: [AgendaEventModel]) -> AgendaDaySection {
            let sectionDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: day)) ?? Date()
            return AgendaDaySection(date: sectionDate, events: events, isToday: calendar.isDateInToday(sectionDate))
        }
        func daily() -> AgendaEventModel { Self.teams("10:30", "10:55", "PZU 1f Daily", recurring: true) }
        return [
            section(11, [AgendaEventModel(title: "(no title)", status: .untimed)]),
            section(14, [daily(), Self.teams("14:30", "16:00", "1F_Refinement_części wspólne")]),
            section(15, [
                Self.teams("10:00", "11:30", "1F - refinement - Widok 360", status: .tentative),
                daily(),
                AgendaEventModel(startTime: "11:00", endTime: "11:30", title: "Status OChK Warta Apreel LZ - docelowa seria",
                                 subtitle: "https://warta.zoom.us/j/96167021773?pwd=iYUkDF4gwzSekLJqdD…",
                                 status: .tentative, hasLinkIcon: true),
                Self.teams("13:30", "15:00", "Canceled: 1F_Refinement_części wspólne", status: .cancelled)
            ]),
            section(16, [daily(), Self.teams("11:30", "11:55", "Feniks - ustalenie kryteriów do wyświetlania listy leadów/wznowień 1F")]),
            section(17, [daily(), Self.teams("13:30", "14:00", "1F Nurty / synchro")]),
            section(18, [Self.teams("09:00", "09:30", "FW: Dashboard - zakres i założenia MVP", status: .tentative), daily()]),
            section(19, [])
        ]
    }

    /// A sample Teams meeting.
    private static func teams(_ start: String, _ end: String, _ title: String, status: EventStatus = .confirmed,
                              recurring: Bool = false) -> AgendaEventModel {
        AgendaEventModel(startTime: start, endTime: end, title: title, subtitle: "Spotkanie w aplikacji Microsoft Teams",
                         status: status, videoService: .teams, isRecurring: recurring)
    }
}

private extension RGBAColor {
    /// The default theme's accent blue.
    static let mockAccent = RGBAColor(red: 0.30, green: 0.62, blue: 1.0)
}
