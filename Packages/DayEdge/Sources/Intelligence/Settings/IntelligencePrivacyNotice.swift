import SwiftUI
import UI

/// Where Ask's requests are processed — always shown under the Assistant
/// group, one look for both cases. Provider-neutral on purpose: an external
/// provider may pass requests on to other AI providers.
struct IntelligencePrivacyNotice: View {
    @Environment(\.themePalette) private var theme
    /// Answered on this Mac (Apple's on-device model), or by a provider.
    let isLocal: Bool

    private var text: String {
        isLocal
            ? L10n.tr("intelligence.privacy.local", "Your requests and relevant calendar and task data are processed on this Mac.")
            : L10n.tr("intelligence.privacy.external",
                      "Your requests and relevant calendar and task data leave this Mac and may be processed by third-party AI providers.")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "hand.raised")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.settings.secondaryText)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.settings.primaryText.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: AppTheme.Settings.groupRadius, style: .continuous).fill(theme.secondaryControl.hover))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
