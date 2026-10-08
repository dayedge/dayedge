import SwiftUI

/// Moves the panel (SwiftUI's `WindowDragGesture`) — placed as the panel's
/// top band, under the toolbar's controls: what's in front takes a press
/// first, so only empty stretches drag, and an event never does.
package struct WindowDragBackground: View {
    package var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
    }

    package init() {
    }
}
