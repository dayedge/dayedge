import AppKit
import Observation
import SwiftUI
import UI

extension MeetingHUDView {
    // MARK: - Right: actions

    /// Join → Reminder → Dismiss. The reminder's secondary segment owns
    /// all alternate timing choices, so there is no duplicate More menu.
    var rightGroup: some View {
        HStack(spacing: 0) {
            if occurrence.meetingURL != nil {
                joinButton
                Spacer().frame(width: 8)
            }
            reminderSplitButton
            Spacer().frame(width: 3)
            dismissButton
        }
    }

    /// The one saturated action. Reminder and Dismiss remain neutral.
    private var joinButton: some View {
        JoinButton(occurrence: occurrence, action: onJoin)
    }

    private var reminderSplitButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let choices = MeetingReminderChoices.resolve(start: occurrence.start, now: context.date)
            HStack(spacing: 0) {
                Button(action: onSnoozeSmart) {
                    Image(systemName: "alarm")
                        .font(.system(size: 16.5, weight: .medium))
                        .foregroundStyle(theme.primaryText.opacity(0.85))
                        .frame(width: 48, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReminderSegmentButtonStyle(isHovered: isReminderActionHovered))
                .focused($focusedControl, equals: .reminderAction)
                .onHover { isReminderActionHovered = $0 }
                .hoverTooltip(isPresented: isReminderActionHovered, edge: .top) {
                    TooltipLabel(text: choices.primaryTitle, shortcut: "S")
                }
                .accessibilityLabel(choices.primaryTitle)

                Rectangle()
                    .fill(theme.secondaryControl.divider)
                    .frame(width: 0.5, height: 14)
                    .accessibilityHidden(true)

                Menu {
                    ForEach(choices.menu, id: \.self) { option in
                        if option == .custom { Divider() }
                        Button {
                            applyReminder(option)
                        } label: {
                            if option == choices.primary {
                                Label(option.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(option.menuTitle)
                            }
                        }
                    }
                    Divider()
                    Button(L10n.tr("meetinghudview.actions.show.event", "Show Event"), action: toggleEventDetail)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 34, height: 28)
                        .background(theme.secondaryControl.hover.opacity(isReminderMenuHovered ? 1 : 0))
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .focused($focusedControl, equals: .reminderMenu)
                .onHover { isReminderMenuHovered = $0 }
                .hoverTooltip(isPresented: isReminderMenuHovered, edge: .top) {
                    TooltipLabel(text: L10n.tr("meetinghudview.actions.reminder.options", "Reminder options"))
                }
                .accessibilityLabel(L10n.tr("meetinghudview.actions.reminder.options", "Reminder options"))
            }
            .background(theme.secondaryControl.fill, in: Capsule())
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(theme.secondaryControl.border, lineWidth: 0.5))
            .popover(isPresented: $isShowingCustomReminder, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                CustomSnoozePopover(
                    onSnooze: { minutes in
                        isShowingCustomReminder = false
                        onSnoozeDuration(TimeInterval(minutes * 60))
                    },
                    onCancel: { isShowingCustomReminder = false }
                )
            }
        }
    }

    private func applyReminder(_ option: MeetingReminderOption) {
        switch option {
        case .untilStart: onSnoozeSmart()
        case .minutes(let count): onSnoozeDuration(TimeInterval(count * 60))
        case .custom: isShowingCustomReminder = true
        }
    }

    var resetPositionMenuItem: some View {
        Button(L10n.tr("meetinghudview.actions.reset.position", "Reset Position")) { onResetPosition() }
    }

    private var dismissButton: some View {
        UtilityIconButton(systemName: "xmark", size: 12, quieter: true, action: onDismiss)
            .hoverTooltip(L10n.tr("meetinghudview.actions.dismiss", "Dismiss"), shortcut: "Esc")
            .accessibilityLabel(L10n.tr("meetinghudview.actions.dismiss.meeting.reminder", "Dismiss meeting reminder"))
    }
}
