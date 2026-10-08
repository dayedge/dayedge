import SwiftUI
import Domain
import UI

/// Settings → General → Date & time: the standard and compact date styles,
/// each System (the region's order, English names) or Custom…, whose
/// pattern is edited in a sheet. Each row's example is its description.
/// Two rows, so `SettingsGroup` separates them like its own.
struct DateFormatRows: View {
    @AppStorage(GeneralSettings.dateFormatStandardKey) private var standard = ""
    @AppStorage(GeneralSettings.dateFormatCompactKey) private var compact = ""
    @State private var editing: DatePatternTarget?

    var body: some View {
        // One sheet for both rows, hung on the first.
        DateFormatRow(target: .standard, stored: $standard) { editing = .standard }
            .sheet(item: $editing) { target in
                DatePatternSheet(target: target, stored: target == .standard ? $standard : $compact)
            }
        DateFormatRow(target: .compact, stored: $compact) { editing = .compact }
    }
}

/// Which style a custom pattern is for.
enum DatePatternTarget: String, Identifiable {
    case standard, compact

    var id: String { rawValue }
    var title: String { self == .standard ? L10n.tr("dateformatrows.standard", "Standard") : L10n.tr("dateformatrows.compact", "Compact") }
    var style: DateStyle { self == .standard ? .standard : .compact }
    /// What the sheet starts from when nothing is saved yet.
    var suggestion: String { self == .standard ? "EEEE d MMMM yyyy" : "EEEE d MMM" }
}

/// "Standard  [System ▾]" with today's date in that style beneath.
private struct DateFormatRow: View {
    @Environment(\.dateFormatter) private var dateFormatter

    let target: DatePatternTarget
    @Binding var stored: String
    let onEdit: () -> Void

    private enum Choice: Hashable { case system, custom, edit }

    var body: some View {
        SettingsPickerRow(
            title: target.title,
            subtitle: dateFormatter.format(.now, target.style),
            selection: Binding(
                get: { stored.isEmpty ? Choice.system : .custom },
                set: { choice in
                    switch choice {
                    case .system: stored = ""
                    case .custom, .edit: onEdit()
                    }
                }
            ),
            options: stored.isEmpty
                ? [(.system, L10n.tr("dateformatrows.system", "System")), (.custom, L10n.tr("dateformatrows.custom", "Custom…"))]
                : [(.system, L10n.tr(
                    "dateformatrows.system", "System"
                )), (.custom, L10n.tr(
                    "dateformatrows.custom.081ae3", "Custom"
                )), (.edit, L10n.tr(
                    "dateformatrows.edit.custom", "Edit Custom…"
                ))]
        )
    }
}

/// The pattern, its live preview, a short error when it can't be used, the
/// link to the pattern letters, and Cancel · Save (Esc · Return).
private struct DatePatternSheet: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.dateFormatter) private var dateFormatter
    @Environment(\.dismiss) private var dismiss

    let target: DatePatternTarget
    @Binding var stored: String
    @State private var draft: String

    /// Apple's guide to the pattern letters (Unicode TR35).
    static let patternsGuide = URL(string: "https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DataFormatting/Articles/dfDateFormatting10_4.html")!

    init(target: DatePatternTarget, stored: Binding<String>) {
        self.target = target
        self._stored = stored
        self._draft = State(initialValue: stored.wrappedValue.isEmpty ? target.suggestion : stored.wrappedValue)
    }

    private var check: DatePresentationFormatter.PatternCheck {
        var system = dateFormatter
        system.customStandard = nil
        system.customCompact = nil
        return DatePresentationFormatter.validate(draft, using: system)
    }

    private var canSave: Bool { check.isValid && draft != stored }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("dateformatrows.custom.date.format", "Custom \(String(describing: target.title)) Date Format"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.settings.primaryText)

            VStack(alignment: .leading, spacing: 5) {
                label(L10n.tr("dateformatrows.pattern", "Pattern"))
                TextField(target.suggestion, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(save)
                if case .invalid(let reason) = check {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accentRed)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                label(L10n.tr("dateformatrows.preview", "Preview"))
                Group {
                    if case .valid(let preview) = check {
                        Text(preview).foregroundStyle(theme.settings.primaryText)
                    } else {
                        Text("—").foregroundStyle(theme.settings.secondaryText)
                    }
                }
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Link(destination: Self.patternsGuide) {
                HStack(spacing: 2) {
                    Text(L10n.tr("dateformatrows.date.format.patterns", "Date format patterns"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12))
            }
            .tint(theme.settings.tint)

            HStack {
                Spacer()
                Button(L10n.tr("dateformatrows.cancel", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("dateformatrows.save", "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(theme.settings.secondaryText)
    }

    private func save() {
        guard canSave else { return }
        stored = draft
        dismiss()
    }
}
