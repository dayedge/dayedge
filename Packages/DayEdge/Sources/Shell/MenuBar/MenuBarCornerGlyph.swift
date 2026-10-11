import Foundation

/// The small glyph overlapped onto the top-right corner of the menu bar
/// calendar icon (`MenuBarBadgeIcon`) — a "corner glyph". There is room
/// for exactly one, so when several apply the one declared *first* below
/// wins: case order is priority order.
///
/// Adding a new corner glyph:
/// 1. Add a case here, placed by priority.
/// 2. If it needs data the icon doesn't have yet, add a field to
///    `MenuBarCornerGlyphInputs` and fill it in
///    `MenuBarStateController.refresh()`.
/// 3. Say when it applies in `applies(to:)`.
/// 4. Draw its glyph in `MenuBarCornerGlyph.glyph(in:)`
///    (`MenuBarBadgeIcon.swift`). The clear halo that separates it from
///    the calendar outline is shared, so only the glyph itself is needed.
enum MenuBarCornerGlyph: CaseIterable, Equatable {
    /// At least one open task due today or overdue — a "○".
    case tasksDue
    /// The strategy capped an event count; a "+" stands in for the rest.
    case overflow

    func applies(to inputs: MenuBarCornerGlyphInputs) -> Bool {
        switch self {
        case .tasksDue:
            return inputs.hasTasksDueToday
        case .overflow:
            return inputs.isOverflow
        }
    }

    /// The highest-priority glyph that applies, or nil for a bare icon.
    static func resolve(_ inputs: MenuBarCornerGlyphInputs) -> MenuBarCornerGlyph? {
        allCases.first { $0.applies(to: inputs) }
    }
}

/// Everything a corner glyph may depend on. Kept as plain values so the
/// resolution stays a pure, testable function.
struct MenuBarCornerGlyphInputs: Equatable {
    var isOverflow: Bool
    /// Today's agenda has an open task — due today or overdue.
    var hasTasksDueToday = false
}
