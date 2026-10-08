import ServiceManagement
import SwiftUI
import Domain
import UI

struct GeneralSettingsView: View {
    @Environment(AppearanceStore.self) private var appearance
    @AppStorage(GeneralSettings.defaultViewKey) private var defaultView = ViewMode.month.settingsValue
    @AppStorage(GeneralSettings.weekStartKey) private var weekStart = WeekStart.system.rawValue
    @AppStorage(GeneralSettings.showsWeatherKey) private var showsWeather = true
    @AppStorage(GeneralSettings.showsDeclinedKey) private var showsDeclined = false
    @AppStorage(GeneralSettings.showsWeekNumbersKey) private var showsWeekNumbers = false
    @AppStorage(GeneralSettings.dayStartHourKey) private var dayStartHour = GeneralSettings.defaultDayStartHour
    @AppStorage(GeneralSettings.timeFormatKey) private var timeFormat = TimeFormatPreference.system.rawValue
    @Environment(\.timeFormat) private var resolvedTimeFormat
    @AppStorage(DockSettings.showsIconKey) private var showsInDock = false
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    /// Login items need a real app bundle; a bare SwiftPM executable can't
    /// register one, so the row is hidden rather than shown broken.
    private var supportsLoginItem: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var body: some View {
        SettingsPane {
            SettingsGroup(header: L10n.tr(
                "generalsettingsview.startup.presence", "Startup & presence"
            ), footer: L10n.tr(
                "generalsettingsview.dayedge.stays.in.the.menu.bar.either.way", "DayEdge stays in the menu bar either way."
            )) {
                if supportsLoginItem {
                    SettingsToggleRow(title: L10n.tr("generalsettingsview.open.at.login", "Open at login"), isOn: $opensAtLogin)
                }
                SettingsToggleRow(title: L10n.tr("generalsettingsview.show.in.dock", "Show in Dock"), isOn: $showsInDock)
            }
            .onChange(of: opensAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    opensAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

            SettingsGroup(header: L10n.tr(
                "generalsettingsview.appearance", "Appearance"
            ), footer: L10n.tr(
                "generalsettingsview.follows.your.mac.when.apple.7ecfac", "Follows your Mac when Apple System is selected."
            )) {
                SettingsPickerRow(
                    title: L10n.tr("generalsettingsview.theme", "Theme"),
                    selection: Binding(get: { appearance.themeID }, set: { appearance.selectTheme($0) }),
                    options: ThemeCatalog.themes.map { ($0.id, $0.title) }
                )
            }

            SettingsGroup(header: L10n.tr("generalsettingsview.calendar", "Calendar")) {
                SettingsPickerRow(
                    title: L10n.tr("generalsettingsview.default.view", "Default view"),
                    selection: $defaultView,
                    options: ViewMode.allCases.map { ($0.settingsValue, $0.tooltipTitle) }
                )
                SettingsPickerRow(
                    title: L10n.tr("generalsettingsview.week.starts.on", "Week starts on"),
                    selection: $weekStart,
                    options: WeekStart.allCases.map { ($0.rawValue, $0.title) }
                )
                SettingsPickerRow(
                    title: L10n.tr("generalsettingsview.day.starts.at", "Day starts at"),
                    selection: $dayStartHour,
                    options: GeneralSettings.dayStartHourOptions.map { ($0, resolvedTimeFormat.hour($0)) }
                )
                SettingsToggleRow(title: L10n.tr("generalsettingsview.show.week.numbers", "Show week numbers"), isOn: $showsWeekNumbers)
                SettingsToggleRow(title: L10n.tr("generalsettingsview.show.declined.events", "Show declined events"), isOn: $showsDeclined)
                SettingsToggleRow(title: L10n.tr(
                    "generalsettingsview.show.weather", "Show weather"
                ), subtitle: L10n.tr(
                    "generalsettingsview.in.the.agenda.and.day.view", "In the agenda and Day view"
                ), isOn: $showsWeather)
                if showsWeather {
                    WeatherLocationRow()
                }
            }

            SettingsGroup(header: L10n.tr("generalsettingsview.date.time", "Date & time")) {
                SettingsPickerRow(
                    title: L10n.tr("generalsettingsview.time.format", "Time format"),
                    selection: $timeFormat,
                    options: TimeFormatPreference.allCases.map { ($0.rawValue, timeFormatTitle($0)) }
                )
                DateFormatRows()
            }
        }
    }

    /// Each option with a live example: "System (5:14pm)".
    private func timeFormatTitle(_ preference: TimeFormatPreference) -> String {
        let example = TimeFormat.presentation(preference).time(hour: 17, minute: 14)
        switch preference {
        case .system: return L10n.tr("generalsettingsview.system", "System (\(String(describing: example)))")
        case .twentyFourHour: return L10n.tr("time.format.24.example", "24-hour (\(example))")
        case .twelveHour: return L10n.tr("time.format.12.example", "12-hour (\(example))")
        }
    }
}
