import SwiftUI
import UI

struct MenuBarSettingsView: View {
    @AppStorage(MenuBarEventIndicatorSettings.enabledKey)
    private var isEnabled = MenuBarEventIndicatorConfiguration.default.isEnabled
    @AppStorage(MenuBarEventIndicatorSettings.leadTimeKey)
    private var leadTimeMinutes = MenuBarEventIndicatorConfiguration.default.leadTimeMinutes
    @AppStorage(MenuBarEventIndicatorSettings.showTitleKey)
    private var showsTitle = MenuBarEventIndicatorConfiguration.default.showsEventTitle
    @AppStorage(MenuBarEventIndicatorSettings.showEndTimeKey)
    private var showsEndTime = MenuBarEventIndicatorConfiguration.default.showsEventEndTime
    @AppStorage(MenuBarEventIndicatorSettings.showAccentKey)
    private var showsAccent = MenuBarEventIndicatorConfiguration.default.showsCalendarAccent
    @AppStorage(MenuBarEventIndicatorSettings.showOngoingKey)
    private var showsOngoing = MenuBarEventIndicatorConfiguration.default.showsOngoingEvents
    @AppStorage(MenuBarEventIndicatorSettings.showRemainingKey)
    private var showsRemaining = MenuBarEventIndicatorConfiguration.default.showsRemainingTimeNearEnd
    @AppStorage(MenuBarEventIndicatorSettings.showFreeTransitionKey)
    private var showsFreeTransition = MenuBarEventIndicatorConfiguration.default.showsFreeTimeTransition
    @AppStorage(MenuBarEventIndicatorSettings.freeTransitionDurationKey)
    private var freeTransitionMinutes = MenuBarEventIndicatorConfiguration.default.freeTimeTransitionMinutes
    @AppStorage(MenuBarEventIndicatorSettings.minimumFreeGapKey)
    private var minimumFreeGapMinutes = MenuBarEventIndicatorConfiguration.default.minimumFreeGapMinutes
    @AppStorage(CallReadinessSettings.leadMinutesKey)
    private var callLeadMinutes = CallReadinessSettings.defaultLeadMinutes
    @AppStorage(PopoverReopenSettings.timeoutMinutesKey)
    private var reopenTimeoutMinutes = PopoverReopenSettings.defaultMinutes

    var body: some View {
        SettingsPane {
            SettingsGroup(header: L10n.tr(
                "menubarsettingsview.popover", "Popover"
            ), footer: L10n.tr(
                "menubarsettingsview.after.that.dayedge.opens.on.today", "After that, DayEdge opens on today."
            )) {
                SettingsPickerRow(
                    title: L10n.tr("menubarsettingsview.keep.last.view.for", "Keep last view for"),
                    selection: $reopenTimeoutMinutes,
                    minutes: PopoverReopenSettings.presetMinutes,
                    zeroLabel: L10n.tr("menubarsettingsview.never", "Never")
                )
            }

            SettingsGroup(header: L10n.tr("menubar.item.section", "Menu Bar Item")) {
                MenuBarItemRows()
            }

            SettingsGroup(header: L10n.tr("menubarsettingsview.quick.join", "Quick Join")) {
                SettingsPickerRow(
                    title: L10n.tr("menubarsettingsview.show.join.button", "Show Join button"),
                    selection: $callLeadMinutes,
                    minutes: CallReadinessSettings.leadMinuteOptions
                )
            }

            SettingsGroup(header: L10n.tr("menubarsettingsview.upcoming.event", "Upcoming event")) {
                SettingsToggleRow(title: L10n.tr("menubarsettingsview.show.upcoming.event", "Show upcoming event"), isOn: $isEnabled)
                Group {
                    SettingsPickerRow(title: L10n.tr("menubarsettingsview.show", "Show"), selection: $leadTimeMinutes, minutes: [5, 10, 15, 30, 60])
                    SettingsToggleRow(title: L10n.tr("menubarsettingsview.title", "Title"), isOn: $showsTitle)
                    SettingsToggleRow(title: L10n.tr("menubarsettingsview.end.time", "End time"), isOn: $showsEndTime)
                    SettingsToggleRow(title: L10n.tr("menubarsettingsview.calendar.color", "Calendar color"), isOn: $showsAccent)
                }
                .settingsDependent(on: isEnabled)
            }

            SettingsGroup(header: L10n.tr("menubarsettingsview.current.event", "Current event")) {
                SettingsToggleRow(title: L10n.tr("menubarsettingsview.show.now", "Show “Now”"), isOn: $showsOngoing)
                SettingsToggleRow(title: L10n.tr("menubarsettingsview.countdown.final.10.minutes", "Countdown final 10 minutes"), isOn: $showsRemaining)
                    .settingsDependent(on: showsOngoing)
            }
            .settingsDependent(on: isEnabled)

            SettingsGroup(
                header: L10n.tr("menubarsettingsview.between.events", "Between events"),
                footer: L10n.tr(
                    "menubarsettingsview.shown.briefly.when.the.gap.0b2237", "Shown briefly when the gap before your next event is long enough."
                )
            ) {
                SettingsToggleRow(title: L10n.tr("menubarsettingsview.show.free.time", "Show free time"), isOn: $showsFreeTransition)
                Group {
                    SettingsPickerRow(title: L10n.tr(
                        "menubarsettingsview.duration", "Duration"
                    ), selection: $freeTransitionMinutes, minutes: [0, 5, 10], zeroLabel: L10n.tr(
                        "menubarsettingsview.briefly", "Briefly"
                    ))
                    SettingsPickerRow(title: L10n.tr("menubarsettingsview.minimum.break", "Minimum break"), selection: $minimumFreeGapMinutes, minutes: [15, 30])
                }
                .settingsDependent(on: showsFreeTransition)
            }
            .settingsDependent(on: isEnabled)
        }
        .onAppear {
            callLeadMinutes = CallReadinessSettings.normalizedLeadMinutes(callLeadMinutes)
        }
    }
}
