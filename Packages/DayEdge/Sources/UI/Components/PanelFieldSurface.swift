import SwiftUI

/// The surface of the toolbar row's field — the search field while a query
/// is typed, and Ask's composer: the search palette's material, fill and
/// restrained shadow, inset from the panel's edges by the caller. Its top
/// edge sits a little low (`verticalOffset`, optical) and its bottom
/// comes up by twice that, so the glyph and text are centred in it (one
/// row: 36pt). Drawing only — the content keeps its coordinates.
package struct PanelFieldSurface: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.colorSchemeContrast) private var contrast

    /// The toolbar field's corners — the search palette's too.
    package static let cornerRadius: CGFloat = 17
    /// Purely optical: the surface sits this much lower than its content.
    package static let verticalOffset: CGFloat = 3

    package static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    package var body: some View {
        let shape = Self.shape
        ThemedSurface(role: .transient, fill: theme.searchSurface, shape: shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(theme.chat.composerStrokeIncreased, lineWidth: 0.5)
                }
            }
            .surfaceElevation(.transient, fallback: .init(color: theme.chrome.searchShadow, radius: 11, y: 3))
            .padding(.bottom, 2 * Self.verticalOffset)
            .offset(y: Self.verticalOffset)
            .allowsHitTesting(false)
    }

    package init() {
    }
}
