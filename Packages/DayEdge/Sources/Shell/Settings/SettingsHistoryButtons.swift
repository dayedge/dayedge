import SwiftUI
import UI

/// Back/forward buttons for the Settings window, as one Liquid Glass
/// capsule on macOS 26 (material fallback elsewhere).
struct SettingsHistoryButtons: View {
    @Environment(\.themePalette) private var theme

    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("chevron.left", help: L10n.tr("settingshistorybuttons.back", "Back"), enabled: canGoBack, action: onBack)
                .keyboardShortcut("[", modifiers: .command)
            Rectangle()
                .fill(theme.settings.divider)
                .frame(width: 0.5, height: 16)
            button("chevron.right", help: L10n.tr("settingshistorybuttons.forward", "Forward"), enabled: canGoForward, action: onForward)
                .keyboardShortcut("]", modifiers: .command)
        }
        .settingsGlassCapsule()
    }

    private func button(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.settings.primaryText.opacity(enabled ? 0.9 : 0.3))
        .disabled(!enabled)
        .hoverTooltip(help, edge: .bottom)
    }
}

private extension View {
    func settingsGlassCapsule() -> some View {
        modifier(NavigationSurfaceModifier())
    }
}
