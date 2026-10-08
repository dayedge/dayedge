import Foundation

/// The small glyph overlapped onto the top-right corner of the menu bar
/// calendar icon (`MenuBarBadgeIcon`) — a "corner badge". There is room
/// for exactly one, so when several apply the one declared *first* below
/// wins: case order is priority order.
///
/// Adding a new corner badge:
/// 1. Add a case here, placed by priority.
/// 2. If it needs data the icon doesn't have yet, add a field to
///    `MenuBarCornerBadgeInputs` and fill it in
///    `MenuBarStateController.refresh()`.
/// 3. Say when it applies in `applies(to:)`.
/// 4. Draw its glyph in `MenuBarCornerBadge.glyph(in:)`
///    (`MenuBarBadgeIcon.swift`). The clear halo that separates it from
///    the calendar outline is shared, so only the glyph itself is needed.
enum MenuBarCornerBadge: CaseIterable, Equatable {
    /// At least one open task due today or overdue — a "○".
    case tasksDue
    /// More than `MenuBarCornerBadge.maxDisplayedValue` — the digit is
    /// clamped and a "+" stands in for the rest.
    case overflow

    /// The calendar icon shows exactly one digit.
    static let maxDisplayedValue = 9

    func applies(to inputs: MenuBarCornerBadgeInputs) -> Bool {
        switch self {
        case .tasksDue:
            return inputs.hasTasksDueToday
        case .overflow:
            return inputs.badgeValue > Self.maxDisplayedValue
        }
    }

    /// The highest-priority badge that applies, or nil for a bare icon.
    static func resolve(_ inputs: MenuBarCornerBadgeInputs) -> MenuBarCornerBadge? {
        allCases.first { $0.applies(to: inputs) }
    }
}

/// Everything a corner badge may depend on. Kept as plain values so the
/// resolution stays a pure, testable function.
struct MenuBarCornerBadgeInputs: Equatable {
    /// The number the calendar icon represents, before clamping.
    var badgeValue: Int
    /// Today's agenda has an open task — due today or overdue.
    var hasTasksDueToday = false
}
