import AppKit
import Observation
import SwiftUI
import UI

@MainActor
@Observable
final class MeetingTakeoverState {
    var occurrence: MeetingHUDOccurrence
    var now: Date
    var activeDisplayID: CGDirectDisplayID
    var isExiting = false
    var isEventHeaderFocused = false
    var isCustomSnoozePresented = false
    var detailToggleRequest: UUID?
    var customReminderRequest: UUID?

    init(occurrence: MeetingHUDOccurrence, now: Date, activeDisplayID: CGDirectDisplayID) {
        self.occurrence = occurrence
        self.now = now
        self.activeDisplayID = activeDisplayID
    }
}

/// The same identity and clock composition on every display. Only the action
/// slot changes, so pointer migration never shifts the title or timer.
struct MeetingTakeoverView: View {
    @Environment(\.themePalette) var theme
    @Environment(\.timeFormat) var timeFormat

    let state: MeetingTakeoverState
    let displayID: CGDirectDisplayID
    let onJoin: () -> Void
    let onSnoozeSmart: () -> Void
    let onSnoozeDuration: (TimeInterval) -> Void
    let onDismiss: () -> Void

    @State var showingCustomSnooze = false
    @State var showingDetails = false
    @State var lastDetailDismissAt: Date = .distantPast
    @State var hasAppeared = false
    @State var isHeaderHovered = false
    @State var isReminderPrimaryHovered = false
    @State var isReminderMenuHovered = false
    @State var isControlsVisible = false
    @FocusState var isHeaderFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) var displayScale

    var occurrence: MeetingHUDOccurrence { state.occurrence }
    var isActive: Bool { displayID == state.activeDisplayID }
    var secondsToStart: Int { Int(ceil(occurrence.start.timeIntervalSince(state.now))) }
    var isStarted: Bool { secondsToStart <= 0 }
    var snoozeChoices: MeetingReminderChoices {
        .resolve(start: occurrence.start, now: state.now)
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                1.08,
                max(0.45, min(
                    (geometry.size.width - 48) / AppTheme.MeetingTakeover.contentWidth,
                    (geometry.size.height - 32) / AppTheme.MeetingTakeover.referenceContentHeight
                ))
            )
            let scaledHeight = AppTheme.MeetingTakeover.referenceContentHeight * scale
            let centerY = max(
                16 + scaledHeight / 2,
                min(geometry.size.height * 0.45, geometry.size.height - 16 - scaledHeight / 2)
            )
            ZStack {
                background
                    .opacity(state.isExiting ? 0 : 1)
                VStack(spacing: 0) {
                    identity
                    Spacer().frame(height: AppTheme.MeetingTakeover.identityTimerGap)
                    timer
                    Spacer().frame(height: AppTheme.MeetingTakeover.timerActionGap)
                    actionSlot
                }
                .frame(
                    width: AppTheme.MeetingTakeover.contentWidth,
                    height: AppTheme.MeetingTakeover.referenceContentHeight
                )
                .scaleEffect(scale)
                .frame(
                    width: AppTheme.MeetingTakeover.contentWidth * scale,
                    height: scaledHeight
                )
                .position(x: geometry.size.width / 2, y: centerY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()

        .onAppear {
            withAnimation(.easeOut(duration: 0.26)) { hasAppeared = true }
            if reduceMotion {
                isControlsVisible = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.easeOut(duration: 0.19)) { isControlsVisible = true }
                }
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                showingCustomSnooze = false
                showingDetails = false
                if isHeaderHovered { NSCursor.pop(); isHeaderHovered = false }
                state.isEventHeaderFocused = false
            }
        }
        .onChange(of: occurrence.id) { _, _ in showingDetails = false }
        .onChange(of: showingCustomSnooze) { _, showing in
            state.isCustomSnoozePresented = showing
        }
        .onChange(of: state.detailToggleRequest) { _, request in
            if request != nil && isActive { toggleEventDetails() }
        }
        .onChange(of: state.customReminderRequest) { _, request in
            if request != nil && isActive { showingCustomSnooze = true }
        }
    }

    var background: some View {
        TakeoverBackdrop(
            style: .current(theme: theme),
            reduceTransparency: reduceTransparency,
            increasedContrast: contrast == .increased
        )
    }

    static func timerString(seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}

struct TakeoverButtonStyle: ButtonStyle {
    var isPrimary = false
    var isQuiet = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, isPrimary: isPrimary, isQuiet: isQuiet)
    }

    private struct StyledButton: View {
        @Environment(\.themePalette) var theme

        let configuration: ButtonStyle.Configuration
        let isPrimary: Bool
        let isQuiet: Bool

        @State private var isHovering = false
        @Environment(\.accessibilityReduceMotion) var reduceMotion
        @Environment(\.colorSchemeContrast) private var contrast

        var fill: Color {
            if isPrimary { return theme.nativeControlAccent }
            if contrast == .increased { return (isHovering ? theme.meetingTakeover.strongActionHover : theme.meetingTakeover.strongActionFill) }
            if isQuiet { return (isHovering ? theme.meetingTakeover.quietActionHover : theme.meetingTakeover.quietActionFill) }
            return isHovering
                ? theme.meetingTakeover.actionSurfaceHover
                : theme.meetingTakeover.actionSurface
        }

        var body: some View {
            configuration.label
                .font(.system(size: isPrimary ? 26 : 19, weight: .semibold))
                .foregroundStyle(isPrimary ? theme.onAccentText : theme.primaryText)
                .background(fill, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        (isPrimary ? theme.meetingTakeover.primaryActionKeyline : theme.meetingTakeover.secondaryActionKeyline), lineWidth: 1
                    )
                }
                .brightness(configuration.isPressed ? -0.07 : 0)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .shadow(
                    color: isPrimary ? theme.chrome.primaryActionShadow : .clear,
                    radius: 8, y: 3
                )
                .contentShape(Capsule())
                .onHover { isHovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
        }
    }
}
