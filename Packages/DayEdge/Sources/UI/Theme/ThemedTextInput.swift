import SwiftUI

extension View {
    /// A text field in the theme: its cursor drawn in the theme's caret colour (`editor.caret`), which stays readable in
    /// dark themes, where the app's tint is a darkened button fill.
    package func themedTextInput() -> some View { modifier(ThemedTextInput()) }
}

private struct ThemedTextInput: ViewModifier {
    @Environment(\.themePalette) private var theme

    func body(content: Content) -> some View {
        content.tint(theme.editor.caret)
    }
}
