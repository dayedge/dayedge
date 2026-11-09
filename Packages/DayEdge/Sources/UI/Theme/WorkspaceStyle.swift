import SwiftUI

/// The panel a view is drawn in: the menu-bar popover, or the Command
/// Window's wider workspaces. Shared views keep their look in the popover
/// and take the workspace roles below in the Command Window.
package enum PanelLayout {
    case compact
    case wide
}

private struct PanelLayoutKey: EnvironmentKey {
    static let defaultValue = PanelLayout.compact
}

extension EnvironmentValues {
    /// Set to `.wide` at the Command Window's root.
    package var panelLayout: PanelLayout {
        get { self[PanelLayoutKey.self] }
        set { self[PanelLayoutKey.self] = newValue }
    }
}

/// The Command Window's structure and selection, one set for every
/// workspace: content first, then the selection, then structure, with the
/// separators barely there. Derived from each theme's own tokens, so every
/// theme keeps its character without a rule of its own.
package struct WorkspaceColors {
    /// Dense, repeated guides: month cells, the timeline's hours.
    package let gridHairline: Color
    /// Light divisions: the command bar's and footer's edges, sections
    /// inside a sidebar.
    package let sectionSeparator: Color
    /// Between two working regions: grid │ agenda, sidebar │ content.
    package let structuralDivider: Color
    /// A selected item: neutral, and kept while focus moves on.
    package let selectedSurface: Color
    /// The selected day in a month grid: the whole cell, faintly in the
    /// theme's today accent — the compact calendar's colour family.
    package let selectedDaySurface: Color
    /// Days of the month shown: a touch lighter than the days around it in
    /// every theme, so its shape reads as one region without any outline.
    package let displayedMonthSurface: Color
    /// Days from the months either side.
    package let adjacentMonthSurface: Color
    /// An action that deletes (Delete Task…, Remove from Calendar…).
    package let destructive: Color
    /// A month cell's day strip: its meetings, in their calendars' colours
    /// at this opacity — quieter than the chips above.
    package let busyStripOpacity: Double
}

extension ThemePaletteValues {
    package var workspace: WorkspaceColors {
        WorkspaceColors(
            // About half the popover's grid rule.
            gridHairline: chrome.gridRule.opacity(0.5),
            sectionSeparator: chrome.gridRule,
            structuralDivider: chrome.divider,
            selectedSurface: chrome.rowSelection,
            selectedDaySurface: todayAccent.opacity(isLight ? 0.10 : 0.14),
            // The month shown is lifted toward a lighter surface — a touch
            // of the ink on dark windows, paper over a light (often grey)
            // canvas — and its neighbours keep the window's: they recede
            // rather than turn into darker tiles. On a pure white window
            // nothing is lighter, so a whisper on the neighbours keeps the
            // month's shape.
            displayedMonthSurface: isLight ? .white.opacity(0.65) : neutralInk.opacity(0.03),
            adjacentMonthSurface: isLight ? neutralInk.opacity(0.015) : .clear,
            destructive: accentRed,
            busyStripOpacity: isLight ? 0.55 : 0.6
        )
    }

    /// A dense guide line (an hour, a cell edge) in `layout`.
    package func gridRule(in layout: PanelLayout) -> Color {
        layout == .wide ? workspace.gridHairline : chrome.gridRule
    }
}

extension ThemePalette {
    package func gridRule(in layout: PanelLayout) -> Color { values.gridRule(in: layout) }
}

/// One of the three separator strengths, one physical pixel thick.
package struct WorkspaceRule: View {
    package enum Role {
        case gridHairline
        case section
        case structural
    }

    @Environment(\.themePalette) private var theme
    @Environment(\.displayScale) private var displayScale

    package let role: Role
    package var axis: Axis = .horizontal

    package var body: some View {
        let thickness = 1 / max(displayScale, 1)
        Rectangle()
            .fill(color)
            .frame(width: axis == .vertical ? thickness : nil, height: axis == .horizontal ? thickness : nil)
    }

    private var color: Color {
        switch role {
        case .gridHairline: theme.workspace.gridHairline
        case .section: theme.workspace.sectionSeparator
        case .structural: theme.workspace.structuralDivider
        }
    }

    package init(_ role: Role, axis: Axis = .horizontal) {
        self.role = role
        self.axis = axis
    }
}

/// A selected row in the Command Window's lists.
package struct WorkspaceSelectionSurface: View {
    @Environment(\.themePalette) private var theme

    package var body: some View {
        ThemedSurface(role: .selection, fill: theme.workspace.selectedSurface,
                      shape: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    package init() {}
}
