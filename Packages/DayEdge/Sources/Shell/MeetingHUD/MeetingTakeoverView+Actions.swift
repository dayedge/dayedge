import AppKit
import Observation
import SwiftUI
import UI

extension MeetingTakeoverView {
    var actionSlot: some View {
        ZStack {
            if isActive {
                VStack(spacing: 18) {
                    primaryAction
                    HStack(spacing: 18) {
                        reminderSplitButton
                        Button(action: onDismiss) {
                            HStack(spacing: 10) {
                                Text(L10n.tr("meetingtakeoverview.actions.dismiss", "Dismiss"))
                                keycap("esc")
                            }
                            .frame(width: 170, height: 54)
                        }
                        .buttonStyle(TakeoverButtonStyle(isQuiet: true))
                        .hoverTooltip(L10n.tr("meetingtakeoverview.actions.dismiss", "Dismiss"), shortcut: "Esc")
                        .accessibilityLabel(L10n.tr("meetingtakeoverview.actions.dismiss.meeting.reminder", "Dismiss meeting reminder"))
                    }
                }
                .transition(.opacity)
            } else {
                Label(L10n.tr("meetingtakeoverview.actions.controls.are.on.the.5f58ce", "Controls are on the display with your pointer"), systemImage: "display")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.secondaryText)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: AppTheme.MeetingTakeover.actionSlotHeight)
        .opacity(isControlsVisible && !state.isExiting ? 1 : 0)
    }

    private var primaryAction: some View {
        Button(action: occurrence.meetingURL == nil ? toggleEventDetails : onJoin) {
            ZStack {
                HStack(spacing: 15) {
                    Image(systemName: occurrence.meetingURL == nil ? "calendar" : "video.fill")
                    Text(occurrence.meetingURL == nil ? L10n.tr("meetingtakeoverview.actions.open.event", "Open Event") : L10n.tr("meetingtakeoverview.actions.join", "Join"))
                }
                .font(.system(size: 26, weight: .semibold))
                if occurrence.meetingURL != nil {
                    HStack {
                        Spacer()
                        keycap("↵", onAccent: true)
                            .padding(.trailing, 24)
                    }
                }
            }
            .frame(
                width: occurrence.meetingURL == nil ? 300 : AppTheme.MeetingTakeover.joinWidth,
                height: AppTheme.MeetingTakeover.joinHeight
            )
        }
        .buttonStyle(TakeoverButtonStyle(isPrimary: true))
        .accessibilityLabel(occurrence.meetingURL == nil ? L10n.tr(
            "meetingtakeoverview.actions.open.event.details", "Open event details"
        ) : L10n.tr(
            "meetingtakeoverview.actions.join.meeting", "Join meeting"
        ))
        .hoverTooltip(
            occurrence.meetingURL == nil ? L10n.tr(
                "meetingtakeoverview.actions.open.event.details", "Open event details"
            ) : L10n.tr(
                "meetingtakeoverview.actions.join.meeting", "Join meeting"
            ),
            shortcut: occurrence.meetingURL == nil ? nil : "↵"
        )
    }

    private var reminderSplitButton: some View {
        HStack(spacing: 0) {
            Button { applySnooze(snoozeChoices.primary) } label: {
                Text(snoozeChoices.primaryTitle)
                    .frame(width: 254, height: 54)
                    .contentShape(Rectangle())
                    .background(theme.meetingTakeover.reminderHover.opacity(isReminderPrimaryHovered ? 1 : 0))
            }
            .buttonStyle(.plain)
            .onHover { isReminderPrimaryHovered = $0 }
            .hoverTooltip(isPresented: isReminderPrimaryHovered, edge: .top) {
                TooltipLabel(text: snoozeChoices.primaryTitle)
            }
            .accessibilityLabel(isStarted ? L10n.tr(
                "meetingtakeoverview.actions.remind.in.1.minute", "Remind in 1 minute"
            ) : L10n.tr(
                "meetingtakeoverview.actions.remind.at.start", "Remind at start"
            ))

            Rectangle()
                .fill(theme.meetingTakeover.iconFill)
                .frame(width: max(0.5, 1 / displayScale), height: 22)
                .accessibilityHidden(true)

            Menu {
                ForEach(snoozeChoices.menu, id: \.self) { option in
                    if option == .custom { Divider() }
                    Button {
                        applySnooze(option)
                    } label: {
                        if option == snoozeChoices.primary {
                            Label(option.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(option.menuTitle)
                        }
                    }
                }
                Divider()
                Button(L10n.tr("meetingtakeoverview.actions.show.event", "Show Event"), action: toggleEventDetails)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.meetingTakeover.menuText)
                    .frame(width: 50, height: 54)
                    .contentShape(Rectangle())
                    .background(theme.meetingTakeover.menuHover.opacity(isReminderMenuHovered ? 1 : 0))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 50, height: 54)
            .contentShape(Rectangle())
            .onHover { isReminderMenuHovered = $0 }
            .accessibilityLabel(isStarted ? L10n.tr(
                "meetingtakeoverview.actions.remind.in.1.minute.menu", "Remind in 1 minute. Menu."
            ) : L10n.tr(
                "meetingtakeoverview.actions.remind.at.start.menu", "Remind at start. Menu."
            ))
            .hoverTooltip(isPresented: isReminderMenuHovered, edge: .top) {
                TooltipLabel(text: L10n.tr("meetingtakeoverview.actions.reminder.options", "Reminder options"))
            }
        }
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(theme.primaryText)
        .background(theme.meetingTakeover.actionSurface, in: Capsule())
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(theme.meetingTakeover.actionKeyline, lineWidth: 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isReminderPrimaryHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isReminderMenuHovered)
        .popover(isPresented: $showingCustomSnooze, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            CustomSnoozePopover(
                onSnooze: { minutes in
                    showingCustomSnooze = false
                    onSnoozeDuration(TimeInterval(minutes * 60))
                },
                onCancel: { showingCustomSnooze = false }
            )
        }
    }

    private func applySnooze(_ option: MeetingReminderOption) {
        switch option {
        case .untilStart:
            onSnoozeSmart()
        case .minutes(let count):
            onSnoozeDuration(TimeInterval(count * 60))
        case .custom:
            showingCustomSnooze = true
        }
    }

    private func keycap(_ text: String, onAccent: Bool = false) -> some View {
        KeyboardShortcutKey(text, size: .large, onAccent: onAccent)
    }
}
