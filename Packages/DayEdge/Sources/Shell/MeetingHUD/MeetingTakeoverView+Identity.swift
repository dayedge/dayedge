import AppKit
import Observation
import SwiftUI
import UI

extension MeetingTakeoverView {
    var identity: some View {
        Button(action: toggleEventDetails) {
            VStack(spacing: 0) {
            ZStack {
                Circle().fill(theme.meetingTakeover.iconFill)
                Circle().strokeBorder(theme.meetingTakeover.iconKeyline, lineWidth: 0.5)
                if let name = occurrence.videoService?.iconResourceName {
                    BrandIcon(resourceName: name)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: occurrence.videoService == nil ? "calendar" : "video")
                        .font(.system(size: 18, weight: .medium))
                }
            }
            .frame(
                width: AppTheme.MeetingTakeover.iconDiameter,
                height: AppTheme.MeetingTakeover.iconDiameter
            )
            .foregroundStyle(theme.primaryText)

            HStack(spacing: 6) {
                Circle().fill(occurrence.calendarColor).frame(width: 7, height: 7)
                Text(metadata)
                    .font(.system(size: AppTheme.MeetingTakeover.metadataFontSize, weight: .medium))
                    .foregroundStyle((isHeaderHovered ? theme.meetingTakeover.metadataHover : theme.meetingTakeover.metadata))
            }
            .padding(.top, 16)

            Text(occurrence.title)
                .font(.system(size: AppTheme.MeetingTakeover.titleFontSize, weight: .bold))
                .foregroundStyle((isHeaderHovered ? theme.meetingTakeover.titleHover : theme.meetingTakeover.title))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .padding(.top, 18)
                .overlay(alignment: .trailing) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.meetingTakeover.disclosure)
                        .opacity(isHeaderHovered ? 1 : 0)
                        .offset(x: 24, y: 9)
                        .accessibilityHidden(true)
                }

            Text(timeFormat.range(occurrence.start, occurrence.end))
                .font(.system(size: AppTheme.MeetingTakeover.eventTimeFontSize, weight: .medium).monospacedDigit())
                .foregroundStyle((isHeaderHovered ? theme.meetingTakeover.metadataHover : theme.meetingTakeover.metadata))
                .padding(.top, 10)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isHeaderFocused)
        .disabled(!isActive)
        .hoverTooltip(isPresented: isHeaderHovered && !showingDetails && isActive, edge: .top) {
            TooltipLabel(text: L10n.tr("meetingtakeoverview.identity.show.event", "Show Event"))
        }
        .accessibilityLabel(L10n.tr(
            "meetingtakeoverview.identity.show.event.c7362d",
            "\(String(describing: occurrence.title)), \(String(describing: timeFormat.range(occurrence.start, occurrence.end))). Show event."
        ))
        .accessibilityValue(showingDetails ? L10n.tr("meetingtakeoverview.identity.open", "Open") : L10n.tr("meetingtakeoverview.identity.closed", "Closed"))
        .popover(isPresented: $showingDetails, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            EventDetailPopoverView(event: occurrence.event, date: occurrence.start)
        }
        .onChange(of: showingDetails) { wasShowing, isShowing in
            if wasShowing && !isShowing { lastDetailDismissAt = .now }
        }
        .onHover { hovering in
            guard isActive else { return }
            if hovering != isHeaderHovered {
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            withAnimation(.easeOut(duration: 0.14)) { isHeaderHovered = hovering }
        }
        .opacity(hasAppeared && !state.isExiting ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : state.isExiting ? 0.98 : hasAppeared ? 1 : 0.97)
        .onDisappear {
            if isHeaderHovered { NSCursor.pop(); isHeaderHovered = false }
        }
        .onChange(of: isHeaderFocused) { _, focused in
            state.isEventHeaderFocused = focused && isActive
        }
    }

    private var metadata: String {
        [occurrence.event.calendarName, occurrence.videoService?.displayName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    func toggleEventDetails() {
        if showingDetails {
            showingDetails = false
        } else if Date.now.timeIntervalSince(lastDetailDismissAt) > 0.3 {
            showingDetails = true
        }
    }

    var timer: some View {
        VStack(spacing: 10) {
            ZStack {
                Text(L10n.tr("meetingtakeoverview.identity.starts.in", "Starts in")).opacity(isStarted ? 0 : 1)
                Text(L10n.tr("meetingtakeoverview.identity.started", "Started")).opacity(isStarted ? 1 : 0)
            }
            .font(.system(size: AppTheme.MeetingTakeover.statusFontSize, weight: .semibold))
            .frame(height: 26)
            Text(Self.timerString(seconds: abs(secondsToStart)))
                .font(.system(size: AppTheme.MeetingTakeover.timerFontSize, weight: .light).monospacedDigit())
        }
        .foregroundStyle(timerColor)
        .opacity(hasAppeared && !state.isExiting ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : state.isExiting ? 0.98 : hasAppeared ? 1 : 0.97)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.23), value: isStarted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTimerDescription)
    }

    private var accessibilityTimerDescription: String {
        if isStarted {
            let minutes = max(0, -secondsToStart / 60)
            return minutes == 0 ? L10n.tr(
                "meetingtakeoverview.identity.meeting.just.started", "Meeting just started"
            ) : L10n.tr(
                "meeting.started.minutes", "Meeting started \(minutes) minutes ago"
            )
        }
        let minutes = Int(ceil(Double(secondsToStart) / 60))
        return minutes <= 1 ? L10n.tr(
            "meetingtakeoverview.identity.meeting.starts.in.60011c", "Meeting starts in less than a minute"
        ) : L10n.tr(
            "meeting.starts.minutes", "Meeting starts in \(minutes) minutes"
        )
    }

    private var timerColor: Color {
        if isStarted { return theme.meetingTakeover.started }
        if secondsToStart <= 60 { return theme.meetingTakeover.approaching }
        return theme.primaryText
    }
}
