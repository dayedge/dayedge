import SwiftUI
import UI

/// Where Ask's requests are processed — always shown under the Assistant
/// group, one look for both cases. Provider-neutral on purpose: an external
/// provider may pass requests on to other AI providers.
struct IntelligencePrivacyNotice: View {
    /// Answered on this Mac (Apple's on-device model), or by a provider.
    let isLocal: Bool

    private var text: String {
        isLocal
            ? L10n.tr("intelligence.privacy.local", "Your requests and relevant calendar and task data are processed on this Mac.")
            : L10n.tr("intelligence.privacy.external",
                      "Your requests and relevant calendar and task data leave this Mac and may be processed by third-party AI providers.")
    }

    var body: some View {
        SettingsInformationCallout(text: text, symbol: "hand.raised")
    }
}
