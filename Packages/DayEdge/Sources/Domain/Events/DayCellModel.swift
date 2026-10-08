import Foundation

/// Display model for a single cell in the month grid. View-agnostic so it
/// can be produced by a mock provider today and EventKit later.
package struct DayCellModel: Identifiable, Hashable {
    package let id: Date
    package let date: Date
    package let dayNumber: Int
    package let isCurrentMonth: Bool
    package let isToday: Bool
    package let isSelected: Bool
    package let isWeekend: Bool
    package let dots: [DotStyle]

    package init(date: Date, dayNumber: Int, isCurrentMonth: Bool, isToday: Bool,
                 isSelected: Bool, isWeekend: Bool, dots: [DotStyle]) {
        self.id = date
        self.date = date
        self.dayNumber = dayNumber
        self.isCurrentMonth = isCurrentMonth
        self.isToday = isToday
        self.isSelected = isSelected
        self.isWeekend = isWeekend
        self.dots = dots
    }
}

/// One dot under a day number. `tint` (`color` in views) comes from the
/// event's calendar;
/// `isFilled` reflects the user's own RSVP — filled for accepted (or
/// organizer-owned) events, hollow/dashed for anything not yet accepted.
package struct DotStyle: Hashable {
    package let tint: RGBAColor
    package let isFilled: Bool

    package init(tint: RGBAColor, isFilled: Bool = true) {
        self.tint = tint
        self.isFilled = isFilled
    }

}
