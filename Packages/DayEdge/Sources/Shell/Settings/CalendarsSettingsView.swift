import EventKit
import SwiftUI
import Domain
import Platform
import UI

struct CalendarsSettingsView: View {
    @Environment(\.themePalette) private var theme

    let visibilityStore: SourceVisibilityStore
    let eventStore: EKEventStore
    var indexActivity: CalendarIndexActivity?

    @State private var access = EventKitAccess.status(for: .event)

    @AppStorage(WorkdaySettings.showCountKey) private var showWorkdayCount = true
    @AppStorage(WorkdaySettings.regionCodeKey) private var holidayRegion = WorkdaySettings.automaticRegion
    @AppStorage(WorkdaySettings.workWeekKey) private var workWeekRaw = WorkWeek.automatic.rawValue
    @AppStorage(WorkdaySettings.markHolidaysKey) private var markHolidays = true
    /// Regions the holiday source can serve; nil until (or unless) loaded,
    /// in which case the full macOS region list is offered.
    @State private var supportedRegions: Set<String>?

    var body: some View {
        SettingsPane {
            accessGroup
            if let indexActivity { CalendarIndexSettingsGroup(activity: indexActivity) }
            if access == .granted { calendarsGroups }
            workdaysGroup
        }
        .task { supportedRegions = try? await CachingHolidayProvider.shared.supportedRegions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccess()
        }
    }

    // MARK: Access

    private var accessGroup: some View {
        SettingsGroup(
            header: L10n.tr("calendarssettingsview.access", "Access"),
            footer: access == .granted ? nil
                : L10n.tr(
                    "calendarssettingsview.dayedge.needs.full.access.ba1719",
                    "DayEdge needs full access to your calendars to show your events. You can change this in System Settings › Privacy & Security › Calendars."
                )
        ) {
            SettingsRow(title: L10n.tr("calendarssettingsview.calendars", "Calendars")) {
                HStack(spacing: 8) {
                    StatusDot(color: accessColor)
                    Text(access.title)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.settings.secondaryText)
                    if let action = access.actionTitle {
                        Button(action) { performAccessAction() }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var accessColor: Color {
        switch access {
        case .granted: return theme.settings.granted
        case .denied: return theme.settings.denied
        case .notDetermined: return theme.settings.pending
        }
    }

    private func performAccessAction() {
        switch access {
        case .granted: break
        case .denied: EventKitAccess.openPrivacySettings(for: .event)
        case .notDetermined:
            Task {
                _ = await EventKitAccess.requestAccessIfNeeded(eventStore: eventStore)
                refreshAccess()
                visibilityStore.update(EventKitAccess.calendarSources(eventStore: eventStore))
            }
        }
    }

    private func refreshAccess() {
        access = EventKitAccess.status(for: .event)
        if access == .granted, visibilityStore.allItems.isEmpty {
            visibilityStore.update(EventKitAccess.calendarSources(eventStore: eventStore))
        }
    }

    // MARK: Calendars

    private var calendarsGroups: some View {
        SourceCheckboxGroups(
            store: visibilityStore,
            kind: .calendar,
            title: L10n.tr("calendarssettingsview.calendars", "Calendars"),
            footer: L10n.tr(
                "calendarssettingsview.dayedge.only.uses.the.014fc9",
                "DayEdge only uses the selected calendars. To hide them for a while, use the calendar menu at the bottom of DayEdge."
            )
        )
    }

    // MARK: Workdays

    private var regionOptions: [(value: String, label: String)] {
        let automatic = WorkdaySettings.effectiveRegion(override: WorkdaySettings.automaticRegion)
            .map { L10n.tr(
                "calendarssettingsview.automatic", "Automatic (\(String(describing: HolidayRegionOption.name(for: $0))))"
            ) } ?? L10n.tr(
                "calendarssettingsview.automatic.ac9041", "Automatic"
            )
        return [(WorkdaySettings.automaticRegion, automatic)]
            + HolidayRegionOption.options(supported: supportedRegions).map { ($0.code, $0.label) }
    }

    private var workdaysGroup: some View {
        SettingsGroup(
            header: L10n.tr("calendarssettingsview.workdays", "Workdays"),
            footer: L10n.tr(
                "calendarssettingsview.used.to.count.working.days.1e9b34",
                "Used to count working days and mark public holidays. No events are added to your calendars."
            )
        ) {
            SettingsToggleRow(title: L10n.tr("calendarssettingsview.show.workday.count", "Show workday count"), isOn: $showWorkdayCount)
            SettingsToggleRow(title: L10n.tr("calendarssettingsview.mark.public.holidays", "Mark public holidays"), isOn: $markHolidays)
            SettingsPickerRow(title: L10n.tr("calendarssettingsview.holiday.region", "Holiday region"), selection: $holidayRegion, options: regionOptions)
            SettingsPickerRow(
                title: L10n.tr("calendarssettingsview.work.week", "Work week"),
                selection: $workWeekRaw,
                options: WorkWeek.allCases.map { ($0.rawValue, $0.title) }
            )
        }
    }
}
