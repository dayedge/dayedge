import SwiftUI
import Domain
import UI

struct MenuBarItemRows: View {
    @Environment(\.dateFormatter) private var formatter
    @Environment(\.timeFormat) private var timeFormat
    @AppStorage(MenuBarDateTimeSettings.presentationKey) private var presentation = MenuBarItemPresentation.icon.rawValue
    @AppStorage(MenuBarBadgeSettings.strategyKey) private var badgeStrategy = MenuBarBadgeStrategy.remainingEvents.rawValue
    @AppStorage(MenuBarDateTimeSettings.formatKey) private var format = MenuBarDateTimeFormat.compact.rawValue
    @AppStorage(MenuBarDateTimeSettings.customPatternKey) private var pattern = ""
    @State private var isEditing = false

    private enum Choice: Hashable { case format(MenuBarDateTimeFormat), edit }

    init() {
        _ = MenuBarDateTimeSettings.presentation()
    }

    var body: some View {
        SettingsPickerRow(
            title: L10n.tr("menubarsettingsview.show", "Show"), selection: $presentation,
            options: MenuBarItemPresentation.allCases.map { ($0.rawValue, $0.title) }
        )
        if mode.showsIcon {
            SettingsPickerRow(
                title: L10n.tr("menubarsettingsview.badge", "Badge"), selection: $badgeStrategy,
                options: MenuBarBadgeStrategy.allCases.map { ($0.rawValue, $0.displayName) }
            )
        }
        if mode.showsDateTime {
            SettingsPickerRow(
                title: L10n.tr("menubar.datetime.format", "Format"),
                subtitle: selected.text(at: .now, pattern: pattern, formatter: formatter, timeFormat: timeFormat),
                selection: Binding(get: { Choice.format(selected) }, set: { choice in
                    switch choice {
                    case .format(.custom), .edit: isEditing = true
                    case .format(let preset): format = preset.rawValue
                    }
                }),
                options: choices
            )
            .sheet(isPresented: $isEditing) {
                DatePatternSheet(
                    title: L10n.tr("menubar.datetime.custom.title", "Custom Date & Time Format"),
                    suggestion: "EEE d MMM HH:mm", stored: $pattern, purpose: .menuBar
                ) {
                    format = MenuBarDateTimeFormat.custom.rawValue
                }
            }
        }
    }

    private var mode: MenuBarItemPresentation { MenuBarItemPresentation(rawValue: presentation) ?? .icon }

    private var choices: [(value: Choice, label: String)] {
        let presets = MenuBarDateTimeFormat.allCases.map { (value: Choice.format($0), label: $0.title) }
        return selected == .custom ? presets + [(.edit, L10n.tr("dateformatrows.edit.custom", "Edit Custom…"))] : presets
    }

    private var selected: MenuBarDateTimeFormat { MenuBarDateTimeFormat(rawValue: format) ?? .compact }
}
