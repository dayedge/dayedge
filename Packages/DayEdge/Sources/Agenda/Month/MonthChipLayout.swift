import CoreGraphics
import Domain

/// Which of a day's events the Command Window's month grid shows as chips:
/// all-day first, then by start, as many as the cell has rows for — the
/// last row becomes "+N more" when they don't all fit.
package struct MonthChipLayout: Equatable {
    package let visible: [AgendaEventModel]
    package let overflowCount: Int

    package static let chipHeight: CGFloat = 18
    package static let chipSpacing: CGFloat = 2

    /// How many chip rows fit under the day number in a cell this tall.
    package static func rowCount(cellHeight: CGFloat, headerHeight: CGFloat) -> Int {
        max(Int((cellHeight - headerHeight + chipSpacing) / (chipHeight + chipSpacing)), 0)
    }

    package init(events: [AgendaEventModel], rows: Int) {
        let ordered = events.enumerated().sorted { lhs, rhs in
            if lhs.element.isAllDay != rhs.element.isAllDay { return lhs.element.isAllDay }
            let lhsStart = lhs.element.startDate ?? .distantPast
            let rhsStart = rhs.element.startDate ?? .distantPast
            return lhsStart == rhsStart ? lhs.offset < rhs.offset : lhsStart < rhsStart
        }.map(\.element)
        guard ordered.count > rows else {
            visible = ordered
            overflowCount = 0
            return
        }
        let shown = max(rows - 1, 0)
        visible = Array(ordered.prefix(shown))
        overflowCount = ordered.count - shown
    }
}
