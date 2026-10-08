import Domain
import SwiftUI
import UI

/// The calendar-color dot — static identity marker most of the time,
/// but pulses briefly at the *actual transition* through the meeting's
/// start (never merely because the HUD is showing an already-started
/// meeting — see `runStartPulseIfNeeded`'s guard). `.task(id:)` keyed on
/// the occurrence id both cancels any in-flight pulse when a new
/// occurrence replaces this one and gives each occurrence a clean,
/// reset-to-identity starting state.
struct CalendarColorDot: View {
    let occurrence: MeetingHUDOccurrence

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(occurrence.calendarColor)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .opacity(opacity)
            .task(id: occurrence.id) {
                await runStartPulseIfNeeded()
            }
    }

    private func runStartPulseIfNeeded() async {
        scale = 1.0
        opacity = 1.0
        defer {
            // Cancellation (a new occurrence replaced this one, or the
            // panel was hidden mid-pulse) must never leave the dot
            // stuck at an intermediate scale/opacity.
            if Task.isCancelled {
                scale = 1.0
                opacity = 1.0
            }
        }

        // Only pulse if we're witnessing the real crossing of start —
        // not an already-started meeting reappearing after a snooze, and
        // not one revealed for the first time after sleep/wake with the
        // meeting already underway.
        let now = Date.now
        guard now < occurrence.start else { return }
        let delay = occurrence.start.timeIntervalSince(now)
        try? await Task.sleep(nanoseconds: UInt64((max(delay, 0)) * 1_000_000_000))
        guard !Task.isCancelled else { return }

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.28)) { scale = 1.12 }
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.28)) { scale = 1.0 }
            return
        }

        // Two full "starting now" cycles — clearly noticeable.
        for _ in 0..<2 {
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.75)) { scale = 1.32; opacity = 0.7 }
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.75)) { scale = 1.0; opacity = 1.0 }
            try? await Task.sleep(nanoseconds: 750_000_000)
        }

        // Noticeably gentler breathing for the remainder of the first
        // minute after start, then stops completely — never an
        // indefinite pulse.
        var elapsed: TimeInterval = 3.0
        while elapsed < 60, !Task.isCancelled {
            withAnimation(.easeInOut(duration: 1.0)) { scale = 1.14; opacity = 0.82 }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.0)) { scale = 1.0; opacity = 1.0 }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            elapsed += 2.0
        }
    }
}

/// Press feedback stays inside the left segment; the joined capsule owns
/// the outer shape and the menu segment owns its independent hover.
struct ReminderSegmentButtonStyle: ButtonStyle {
    @Environment(\.themePalette) private var theme

    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? theme.secondaryControl.pressed
                    : theme.secondaryControl.hover.opacity(isHovered ? 1 : 0)
            )
    }
}

/// Shared chrome for the compact HUD's icon-only actions.
struct UtilityIconGlyph: View {
    @Environment(\.themePalette) private var theme

    let systemName: String
    let size: CGFloat
    var quieter: Bool = false

    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(iconColor)
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(theme.chrome.slotHover.opacity(isHovering ? 1 : 0))
            )
            // The full 30×30 square, not just the inscribed circle —
            // the visible hover fill is a circle, but the actual click
            // target must be the whole square (per spec: "Hit target:
            // 30 × 30 pt"). With `Circle()` here instead, the four
            // corners of the frame fell outside the button's hit area
            // and (once the drag layer sits directly behind it) landed
            // on the drag gesture instead of the button — a real,
            // reproducible cause of "clicking Dismiss does nothing."
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }

    private var iconColor: Color {
        if isHovering { return theme.primaryText }
        return quieter ? theme.secondaryText.opacity(0.85) : theme.secondaryText
    }
}

/// A `UtilityIconGlyph` wrapped in a plain tap target — the Dismiss
/// control.
struct UtilityIconButton: View {
    let systemName: String
    let size: CGFloat
    var quieter: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            UtilityIconGlyph(systemName: systemName, size: size, quieter: quieter)
        }
        .buttonStyle(.plain)
    }
}

/// The HUD's primary action — capsule geometry and provider-color source
/// reused from `JoinCallButton`/`CompactJoinButton`, sized up for HUD
/// density. See `MeetingHUDView.joinButton`'s doc comment for why the
/// rest/hover treatment itself isn't an exact copy of those.
struct JoinButton: View {
    @Environment(\.themePalette) private var theme

    let occurrence: MeetingHUDOccurrence
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    private var tintColor: Color { theme.controlAccent }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                iconView
                    .frame(width: 14, height: 14)
                Text(L10n.tr("meetinghudcontrols.join", "Join"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(theme.onAccentText)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                Capsule().fill(tintColor.opacity(isPressed ? 0.85 : (isHovering ? 1 : 0.94)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .hoverTooltip(isPresented: isHovering, edge: .top) {
            TooltipLabel(text: L10n.tr("meetinghudcontrols.join.meeting", "Join meeting"))
        }
        .accessibilityLabel(L10n.tr("meetinghudcontrols.join.meeting", "Join meeting"))
    }

    @ViewBuilder
    private var iconView: some View {
        if let resourceName = occurrence.videoService?.iconResourceName {
            BrandIcon(resourceName: resourceName)
                .foregroundStyle(theme.onAccentText)
        } else {
            Image(systemName: "video.fill")
                .font(.system(size: 13))
        }
    }
}
