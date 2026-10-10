import SwiftUI

/// One of the panel's permanently mounted views (Month, Day, Tasks): on
/// screen, or mounted and hidden. Only its opacity crossfades — clicks,
/// accessibility and order switch at once, and nothing inside animates.
private struct PanelColumn: ViewModifier {
    let isShown: Bool

    func body(content: Content) -> some View {
        content
            .animation(.easeOut(duration: 0.15)) { $0.opacity(isShown ? 1 : 0) }
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
            // The visible scroll surface stays above the hidden ones, so its
            // backdrop samples that content.
            .zIndex(isShown ? 1 : 0)
    }
}

extension View {
    func panelColumn(isShown: Bool) -> some View {
        modifier(PanelColumn(isShown: isShown))
    }
}
