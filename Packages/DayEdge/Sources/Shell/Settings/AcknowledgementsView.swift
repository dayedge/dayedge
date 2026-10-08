import SwiftUI
import UI

/// About → Acknowledgements…: the open-source software, fonts and public
/// data the app is built with. A quiet sheet: a short thank-you, three
/// sections of rows — name, then the licence and a chevron, both muted —
/// highlighted on hover rather than ruled; a row opens its details in the
/// same sheet, with a back button.
struct AcknowledgementsView: View {
    @Environment(\.themePalette) private var theme
    @State private var selection: Acknowledgement?
    @State private var showsThirdPartyLicenses = false

    var body: some View {
        AboutSheet {
            Group {
                if let selection {
                    AcknowledgementDetail(item: selection) { self.selection = nil }
                        .transition(.opacity)
                } else {
                    list.transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: selection)
        }
        .sheet(isPresented: $showsThirdPartyLicenses) { LicenseView(isThirdParty: true) }
    }

    private var list: some View {
        ThemedScrollView(appliesTopEdgeEffect: true, appliesBottomEdgeEffect: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.tr("acknowledgements.title", "Acknowledgements"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.settings.primaryText)
                Text(L10n.tr("acknowledgements.intro", "DayEdge is built with open-source software and public data.\nWe're grateful to the people behind these projects."))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.settings.secondaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                ForEach(Acknowledgement.Kind.allCases, id: \.self) { kind in
                    section(kind)
                        .padding(.top, 26)
                }
                Button(L10n.tr("acknowledgements.full.licenses", "Read full third-party licenses…")) { showsThirdPartyLicenses = true }
                    .buttonStyle(.link)
                    .padding(.top, 22)
            }
            .padding(.horizontal, AcknowledgementMetrics.paddingH)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func section(_ kind: Acknowledgement.Kind) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kind.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(theme.settings.secondaryText.opacity(0.8))
                .padding(.leading, AcknowledgementMetrics.rowPaddingH)
                .padding(.bottom, 6)
            ForEach(Acknowledgement.all.filter { $0.kind == kind }) { item in
                AcknowledgementRow(item: item) { selection = item }
            }
        }
        // Rows' highlight reaches a little past the text column.
        .padding(.horizontal, -AcknowledgementMetrics.rowPaddingH)
    }
}

/// The sheet About opens — Acknowledgements, License: content scrolls
/// under both edges and fades there (the app's thin scroll thumb, its soft
/// edge effects), a slim top bar, and Done floating at the bottom.
struct AboutSheet<Content: View>: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .floatingTopBar { Color.clear.frame(height: 14) }
            .floatingFooterBar {
                HStack {
                    Spacer()
                    Button(L10n.tr("aboutsheet.done", "Done")) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, AcknowledgementMetrics.paddingH)
                .padding(.vertical, 14)
            }
            .frame(width: 700, height: 560)
            .background(theme.settings.background)
    }
}

enum AcknowledgementMetrics {
    static let paddingH: CGFloat = 32
    static let rowPaddingH: CGFloat = 10
}

/// Name — licence ›, the whole row a button, highlighted on hover.
private struct AcknowledgementRow: View {
    @Environment(\.themePalette) private var theme
    let item: Acknowledgement
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(verbatim: item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.settings.primaryText)
                Spacer(minLength: 12)
                Text(item.license)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.settings.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.settings.secondaryText.opacity(0.55))
            }
            .padding(.horizontal, AcknowledgementMetrics.rowPaddingH)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? theme.chrome.rowHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(item.name), \(item.license)")
        .accessibilityHint(L10n.tr("acknowledgements.details", "Shows details"))
    }
}

/// One component, in the same sheet: back, name, licence, homepage,
/// what it does here, and its copyright.
private struct AcknowledgementDetail: View {
    @Environment(\.themePalette) private var theme
    let item: Acknowledgement
    let onBack: () -> Void

    var body: some View {
        ThemedScrollView(appliesTopEdgeEffect: true, appliesBottomEdgeEffect: true) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L10n.tr("acknowledgements.title", "Acknowledgements"))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(theme.settings.tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)

                Text(verbatim: item.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.settings.primaryText)
                    .padding(.top, 18)
                Text(Self.licenseName(item.license))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.settings.secondaryText)
                    .padding(.top, 2)

                Link(destination: item.homepage) {
                    HStack(spacing: 3) {
                        Text(L10n.tr("acknowledgements.homepage", "Homepage"))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13))
                }
                .tint(theme.settings.tint)
                .padding(.top, 14)

                Text(item.role)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.settings.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                Text(item.copyright)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.settings.secondaryText)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AcknowledgementMetrics.paddingH)
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// "MIT" → "MIT License"; names that already say what they are stay.
    static func licenseName(_ short: String) -> String {
        switch short {
        case "MIT": return "MIT License"
        case "Apache 2.0": return "Apache License 2.0"
        case "SIL OFL 1.1": return "SIL Open Font License 1.1"
        case "CC BY 4.0": return "Creative Commons Attribution 4.0"
        case "ODbL 1.0": return "Open Database License 1.0"
        default: return short
        }
    }
}
