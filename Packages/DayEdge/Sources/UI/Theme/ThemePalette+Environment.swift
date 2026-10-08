import AppKit
import SwiftUI

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.opal
}

extension EnvironmentValues {
    package var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

extension View {
    /// The theme's compact-control keyline, where it has one.
    package func compactControlKeyline<S: InsettableShape>(_ theme: ThemePalette, in shape: S) -> some View {
        overlay {
            if let keyline = theme.compactControl?.keyline {
                shape.strokeBorder(keyline, lineWidth: 0.5)
            }
        }
    }
}
