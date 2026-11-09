import SwiftUI
import UI

extension View {
    /// A heading's title that goes to today: Today and its key on hover.
    /// The app's own tooltip, not `.help`: the views are stacked (hidden
    /// ones only faded out), and AppKit's tooltips didn't follow which one
    /// is on screen — Day's never showed.
    func todayTooltip() -> some View {
        hoverTooltip(PanelAction.today.title,
                     shortcut: KeyboardShortcutSettings.shared.shortcut(for: .action(.today))?.displayLabel, edge: .bottom)
    }
}
