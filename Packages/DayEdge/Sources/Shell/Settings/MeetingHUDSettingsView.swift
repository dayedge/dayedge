import SwiftUI
import UI

struct MeetingHUDSettingsView: View {
    var onShowPreview: () -> Void = {}

    @AppStorage(MeetingHUDSettings.enabledKey)
    private var isEnabled = MeetingHUDConfiguration.default.isEnabled
    @AppStorage(MeetingHUDSettings.styleKey)
    private var style = MeetingHUDConfiguration.default.style.rawValue
    @AppStorage(MeetingHUDSettings.leadTimeKey)
    private var leadMinutes = MeetingHUDConfiguration.default.leadTimeMinutes
    @AppStorage(MeetingHUDSettings.playsSoundKey)
    private var playsSound = MeetingHUDConfiguration.default.playsSound
    @AppStorage(MeetingHUDSettings.showForKey)
    private var showFor = MeetingHUDConfiguration.default.showFor.rawValue
    @AppStorage(MeetingHUDSettings.displayKey)
    private var display = MeetingHUDConfiguration.default.display.rawValue
    @AppStorage(MeetingHUDSettings.takeoverBackdropKey)
    private var backdrop = TakeoverBackdropChoice.theme.rawValue

    var body: some View {
        SettingsPane {
            SettingsGroup(
                header: L10n.tr("meetinghudsettingsview.reminder", "Reminder"),
                footer: L10n.tr(
                    "meetinghudsettingsview.a.reminder.with.a.join.a56eff", "A reminder with a Join button appears when a meeting is about to start."
                )
            ) {
                SettingsToggleRow(title: L10n.tr("meetinghudsettingsview.show.meeting.reminder", "Show meeting reminder"), isOn: $isEnabled)
                Group {
                    SettingsPickerRow(
                        title: L10n.tr("meetinghudsettingsview.when", "When"),
                        selection: $leadMinutes,
                        options: [(0, L10n.tr(
                            "meetinghudsettingsview.at.start", "At start"
                        )), (1, L10n.tr(
                            "meetinghudsettingsview.1.min.before", "1 min before"
                        )), (5, L10n.tr(
                            "meetinghudsettingsview.5.min.before", "5 min before"
                        ))]
                    )
                    SettingsPickerRow(
                        title: L10n.tr("meetinghudsettingsview.style", "Style"),
                        selection: $style,
                        options: [(MeetingHUDStyle.compact.rawValue, L10n.tr(
                            "meetinghudsettingsview.compact", "Compact"
                        )), (MeetingHUDStyle.fullScreen.rawValue, L10n.tr(
                            "meetinghudsettingsview.full.screen", "Full screen"
                        ))]
                    )
                    if style == MeetingHUDStyle.fullScreen.rawValue {
                        SettingsPickerRow(
                            title: L10n.tr("meetinghudsettingsview.background", "Background"),
                            selection: $backdrop,
                            options: TakeoverBackdropChoice.allCases.map { ($0.rawValue, $0.title) }
                        )
                    }
                    SettingsToggleRow(title: L10n.tr("meetinghudsettingsview.play.sound", "Play sound"), isOn: $playsSound)
                }
                .settingsDependent(on: isEnabled)
            }

            SettingsGroup(header: L10n.tr("meetinghudsettingsview.meetings", "Meetings")) {
                SettingsPickerRow(
                    title: L10n.tr("meetinghudsettingsview.remind.me.about", "Remind me about"),
                    selection: $showFor,
                    options: [
                        (MeetingHUDShowFor.meetingsWithLink.rawValue, L10n.tr("meetinghudsettingsview.meetings.with.a.call.link", "Meetings with a call link")),
                        (MeetingHUDShowFor.allTimedEvents.rawValue, L10n.tr("meetinghudsettingsview.all.timed.events", "All timed events"))
                    ]
                )
                SettingsPickerRow(
                    title: L10n.tr("meetinghudsettingsview.show.on", "Show on"),
                    selection: $display,
                    options: [
                        (MeetingHUDDisplay.active.rawValue, L10n.tr("meetinghudsettingsview.active.display", "Active display")),
                        (MeetingHUDDisplay.main.rawValue, L10n.tr("meetinghudsettingsview.main.display", "Main display")),
                        (MeetingHUDDisplay.all.rawValue, L10n.tr("meetinghudsettingsview.all.displays", "All displays"))
                    ]
                )
            }
            .settingsDependent(on: isEnabled)

            HStack {
                Spacer()
                Button(L10n.tr("meetinghudsettingsview.preview.reminder", "Preview Reminder")) { onShowPreview() }
            }
        }
        .onAppear {
            leadMinutes = MeetingHUDSettings.normalizedLeadTime(leadMinutes)
        }
    }
}
