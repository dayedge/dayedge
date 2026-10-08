import SwiftUI
import UI

/// About → the app's licence: the full Mozilla Public License 2.0, as
/// shipped in the repository's LICENSE (bundled as `Resources/LICENSE.txt`),
/// in the same sheet as Acknowledgements.
struct LicenseView: View {
    @Environment(\.themePalette) private var theme
    var isThirdParty = false

    static let name = "Mozilla Public License 2.0"

    var body: some View {
        AboutSheet {
            ThemedScrollView(appliesTopEdgeEffect: true, appliesBottomEdgeEffect: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isThirdParty ? L10n.tr("license.third.party.title", "Third-party licenses") : L10n.tr("license.title", "License"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.settings.primaryText)
                    Text(isThirdParty ? L10n.tr("license.third.party.intro", "Licenses and notices for the software, fonts and data used by DayEdge.")
                         : L10n.tr("license.intro", "DayEdge is free and open source under the \(Self.name)."))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.settings.secondaryText)
                        .padding(.top, 6)

                    // Monospaced: the text is laid out with indents and
                    // underlined headings. One view per paragraph — a single
                    // Text this tall is cut off rather than scrolled.
                    LazyVStack(alignment: .leading, spacing: 11) {
                        ForEach(Array((isThirdParty ? Self.thirdPartyParagraphs : Self.paragraphs).enumerated()), id: \.offset) { _, paragraph in
                            Text(verbatim: paragraph)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(theme.settings.primaryText)
                                .lineSpacing(1.5)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 22)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AcknowledgementMetrics.paddingH)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The text split at its blank lines.
    static let paragraphs: [String] = text.components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .newlines) }
        .filter { !$0.isEmpty }

    static let thirdPartyParagraphs = thirdPartyText.components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .newlines) }
        .filter { !$0.isEmpty }

    static let thirdPartyText: String = {
        guard let url = Bundle.module.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "https://github.com/dayedge/dayedge/tree/main/Packages/DayEdge/Sources/Shell/Resources" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// The bundled text; a pointer to it online if it's ever missing.
    static let text: String = {
        guard let url = Bundle.module.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "https://mozilla.org/MPL/2.0/" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }()
}
