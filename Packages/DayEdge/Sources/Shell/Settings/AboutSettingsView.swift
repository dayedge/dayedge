import SwiftUI
import Domain
import UI

struct AboutSettingsView: View {
    @Environment(\.themePalette) private var theme
    @State private var showsAcknowledgements = false
    @State private var showsLicense = false
    /// Replays onboarding over the current settings (nothing is reset).
    var onShowWelcome: () -> Void = {}

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        SettingsPane {
            VStack(spacing: 6) {
                appIcon
                    .padding(.bottom, 2)
                Wordmark(size: 22)
                Text(L10n.tr("aboutsettingsview.version", "Version \(String(describing: version))"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.settings.secondaryText)
                license
                    .padding(.top, 6)
                links
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            SettingsGroup(
                header: L10n.tr("aboutsettingsview.integrations", "Integrations"),
                footer: L10n.tr(
                    "about.integrations.description",
                    """
                    Meeting links in your events are recognized: join with one click from the agenda, the event details or the meeting reminder. \
                    The app opens directly when it's installed.
                    """
                )
            ) {
                SettingsRow(title: "Microsoft Teams") { serviceIcon(.teams) }
                SettingsRow(title: "Zoom") { serviceIcon(.zoom) }
            }

            VStack(spacing: 8) {
                Text(L10n.tr("aboutsettingsview.copyright.2026.dayedge.contributors", "Copyright © 2026 DayEdge contributors"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.settings.secondaryText)
                HStack(spacing: 8) {
                    Button(L10n.tr("aboutsettingsview.acknowledgements", "Acknowledgements…")) { showsAcknowledgements = true }
                    Button(L10n.tr("aboutsettingsview.show.welcome.again", "Show Welcome Again…"), action: onShowWelcome)
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showsAcknowledgements) { AcknowledgementsView() }
        .sheet(isPresented: $showsLicense) { LicenseView() }
    }

    /// "Free and open source · Mozilla Public License 2.0" — the licence
    /// opens its full text.
    private var license: some View {
        HStack(spacing: 5) {
            Text(L10n.tr("aboutsettingsview.free.and.open.source", "Free and open source ·"))
                .foregroundStyle(theme.settings.secondaryText)
            Button(LicenseView.name) { showsLicense = true }
                .buttonStyle(.plain)
                .foregroundStyle(theme.settings.tint)
                .pointerStyle(.link)
                .accessibilityHint(L10n.tr("aboutsettingsview.shows.the.license", "Shows the license"))
        }
        .font(.system(size: 12))
    }

    /// GitHub · Website · Support — link-styled, centered under the name.
    private var links: some View {
        HStack(spacing: 14) {
            Link("GitHub", destination: AppLinks.github)
            Link(L10n.tr("aboutsettingsview.website", "Website"), destination: AppLinks.website)
            Link(destination: AppLinks.kofi) {
                Label(L10n.tr("aboutsettingsview.support.on.ko.fi", "Support on Ko-fi"), systemImage: "cup.and.saucer")
                    .fontWeight(.semibold)
            }
        }
        .font(.system(size: 12))
        .tint(theme.settings.tint)
    }

    /// The app's icon (`Resources/AppIcon.png`, 256 px: sharp at 80 pt on
    /// Retina); the calendar symbol if it's ever missing.
    @ViewBuilder
    private var appIcon: some View {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "calendar.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.controlAccent)
        }
    }

    /// The service's brand mark, as on the Join pill.
    @ViewBuilder
    private func serviceIcon(_ service: VideoConferenceService) -> some View {
        if let resource = service.iconResourceName {
            BrandIcon(resourceName: resource)
                .foregroundStyle(service.tintColor(theme: theme))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        }
    }
}
