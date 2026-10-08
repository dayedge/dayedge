import AppKit
import SwiftUI
import Domain
import UI

/// A single positioned event block in the day timeline. Geometry (position,
/// width, height) is computed upstream by `DayTimelineLayout` plus the
/// parent's pixels-per-minute scale; this view draws the rect it's told to.
///
/// An event the app may edit (`EventEditability`), timed and within this
/// day, can be resized by dragging its top or bottom edge, or moved by
/// dragging its middle: the block follows live, snapped to 15 minutes
/// (`TimelineResize`), and the drop saves through `EventActionCoordinator`
/// (Undo in the notice). A click still opens its details. A repeating event
/// asks which events on the panel's docked `DecisionCard`.
package struct DayTimelineEventView: View {
    @Environment(\.themePalette) private var theme

    package let event: AgendaEventModel
    package let date: Date
    package let height: CGFloat
    package var minuteHeight: CGFloat = AppTheme.Metrics.timelineHourHeight / 60
    package var isOngoing = false
    /// Keyboard selection, and the Return-key detail request.
    package var isKeyboardSelected = false
    package var detailPresentationRequest: EventDetailPresentationRequest?
    package var onDetailPresentationChange: (Bool) -> Void = { _ in }

    @Environment(\.eventActionCoordinator) private var actions
    @Environment(\.timeFormat) private var timeFormat
    @State private var isHovering = false
    @State private var isShowingDetail = false
    /// The edge being dragged and how far, in minutes (raw, unsnapped).
    @State private var dragEdge: TimelineResize.Edge?
    @State private var dragMinutes: Double = 0
    /// Dropped moves waiting for an answer or a save — shared, so a rebuilt
    /// block still shows where the event was dropped.
    @State private var drops = TimelineDropStore.shared
    /// Mirrors `AgendaEventRowView`'s/`AllDayEventTagView`'s same guard:
    /// the system's own outside-click dismissal fires ahead of
    /// `onTapGesture`'s mouse-up recognition, so a click landing right on
    /// the heels of a dismiss is that same click, not a new one — kept in
    /// sync here so Day view's click-to-close behaves identically to
    /// Agenda's rather than only ever opening on tap.
    @State private var lastDismissAt: Date = .distantPast

    private var isTentative: Bool { event.status == .tentative }
    private var isCancelled: Bool { event.status == .cancelled }
    private var showsDetailLines: Bool { displayHeight > 32 }

    // MARK: Resizing

    private var calendar: Calendar { .autoupdatingCurrent }
    private var dayStart: Date { calendar.startOfDay(for: date) }

    /// The event's minutes in this day, when it can be resized here: editable,
    /// timed, starting and ending on this day.
    private var resizableRange: (start: Int, end: Int)? {
        guard actions?.editability(of: event).canEdit == true, !event.isAllDay,
              let start = event.startDate, let end = event.endDate,
              calendar.isDate(start, inSameDayAs: date),
              end <= (calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end) else { return nil }
        return (Int(start.timeIntervalSince(dayStart) / 60), Int(end.timeIntervalSince(dayStart) / 60))
    }

    /// Where the edges are now: the drag's preview, a resize waiting for its
    /// span, or nil (as drawn by the parent).
    private var previewRange: (start: Int, end: Int)? {
        // A drop waiting to be saved — until the event itself has those times.
        if let held = drops.dropped[event.id], let range = resizableRange,
           (held.start, held.end) != range {
            return (held.start, held.end)
        }
        guard let dragEdge, let range = resizableRange else { return nil }
        return TimelineResize.resized(start: range.start, end: range.end, edge: dragEdge, deltaMinutes: dragMinutes)
    }

    private var displayHeight: CGFloat {
        guard let preview = previewRange else { return height }
        return max(CGFloat(preview.end - preview.start) * minuteHeight, 16)
    }

    private var previewOffset: CGFloat {
        guard let preview = previewRange, let range = resizableRange else { return 0 }
        return CGFloat(preview.start - range.start) * minuteHeight
    }

    private func clock(_ minutes: Int) -> String {
        timeFormat.time(minutesSinceMidnight: minutes)
    }

    /// Taller where there's room, so it's easy to catch.
    private var handleHeight: CGFloat { displayHeight >= 32 ? 8 : 5 }

    private func resizeHandle(_ edge: TimelineResize.Edge) -> some View {
        Color.clear
            .frame(height: handleHeight)
            .contentShape(Rectangle())
            // The system's resize pointer for this edge.
            .pointerStyle(.frameResize(position: edge == .top ? .top : .bottom))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        dragEdge = edge
                        dragMinutes = value.translation.height / minuteHeight
                    }
                    .onEnded { _ in finishResize() }
            )
            .accessibilityHidden(true)
    }

    private func finishResize() {
        // Only a drag in progress finishes — a repeat call (the gesture can
        // end twice, also on a block being rebuilt) mustn't ask again and
        // cancel the question just asked.
        guard dragEdge != nil, drops.dropped[event.id] == nil else { return resetDrag() }
        guard let range = resizableRange, let preview = previewRange else { return resetDrag() }
        dragEdge = nil
        dragMinutes = 0
        guard preview != range else { return }
        // Stay where dropped while asking (a repeating event) and saving;
        // back only if cancelled or it failed. Once saved, the event's own
        // times match the drop and it's drawn from them again.
        let eventID = event.id
        let drops = drops
        drops.hold(.init(start: preview.start, end: preview.end), for: eventID)
        let start = dayStart.addingTimeInterval(Double(preview.start) * 60)
        let end = dayStart.addingTimeInterval(Double(preview.end) * 60)
        actions?.editAskingSpan(event, EventChange(start: start, end: end)) { saved in
            if saved {
                // A moved event comes back under a new id; let go of the old
                // one once the calendar has reloaded.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    drops.release(eventID)
                }
            } else {
                drops.release(eventID)
            }
        }
    }

    private func resetDrag() {
        dragEdge = nil
        dragMinutes = 0
    }

    /// Matches Apple Calendar's own convention: an accepted (or
    /// organizer-owned) event gets a full translucent color fill; one
    /// that's not yet accepted gets a diagonal-stripe hatch in the
    /// calendar's own color instead of a flat fill.
    private var fillColor: Color {
        switch event.status {
        case .confirmed, .untimed: return event.color.opacity(theme.eventFillOpacity)
        case .tentative: return event.color.opacity(theme.tentativeEventFillOpacity)
        case .cancelled: return theme.content.cancelledTimelineFill
        }
    }

    private var titleColor: Color {
        if isCancelled { return theme.content.cancelledTimelineText }
        if isTentative { return theme.content.tentativeText }
        return theme.primaryText
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(verbatim: event.title)
                    .font(.system(size: 11, weight: isTentative ? .regular : .semibold))
                    .foregroundStyle(titleColor)
                    .strikethrough(isCancelled)
                    .lineLimit(showsDetailLines ? 2 : 1)

                if let videoService = event.videoService {
                    VideoServiceBadge(service: videoService)
                }
            }

            if showsDetailLines, let subtitle = event.subtitle {
                detailLine(icon: "location", text: subtitle)
            }

            if showsDetailLines {
                timeDetailLine
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: displayHeight, alignment: .top)
        .background {
            fillColor.saturation(theme.eventFillSaturation)
        }
        .background {
            if isTentative {
                DiagonalStripesBackground(color: event.color)
            }
        }
        .brightness((isHovering ? theme.sourcePresentation.eventHoverBrightness : 0)
            + (isOngoing ? theme.sourcePresentation.eventOngoingBrightness : 0))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(
                    isOngoing ? theme.chrome.ongoingEventKeyline : event.color.opacity(isCancelled ? 0 : theme.sourcePresentation.eventBorderOpacity),
                    lineWidth: 1
                )
        )
        .overlay {
            // Persists while the popover is open, independent of hover —
            // same "selected" treatment as the agenda list's rows.
            if isShowingDetail {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(theme.detailSelectionAccent, lineWidth: 1.5)
            } else if isKeyboardSelected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(theme.chrome.keyboardEventKeyline, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if event.isRecurring {
                TimelineRecurrenceBadge(color: titleColor)
            }
        }
        .overlay(alignment: .top) { if resizableRange != nil { resizeHandle(.top) } }
        .overlay(alignment: .bottom) { if resizableRange != nil { resizeHandle(.bottom) } }
        .offset(y: previewOffset)
        // The saved times arrived: draw from the event again.
        .contentShape(Rectangle())
        // Dragging the middle moves it; a click (no real movement) still
        // opens its details.
        // (The edges' own drags take precedence over this one.)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    dragEdge = .body
                    dragMinutes = value.translation.height / minuteHeight
                }
                .onEnded { _ in finishResize() },
            isEnabled: resizableRange != nil
        )
        .onHover { isHovering = $0 }
        // An open hand over an event that moves; a closed one while moving it.
        .pointerStyle(resizableRange == nil ? nil : (dragEdge == .body ? .grabActive : .grabIdle))
        .onChange(of: isShowingDetail) { wasShowing, isShowing in
            if wasShowing, !isShowing {
                lastDismissAt = Date()
            }
            onDetailPresentationChange(isShowing)
        }
        .onChange(of: detailPresentationRequest) { _, request in
            guard request?.eventID == event.id else { return }
            switch request?.action {
            case .toggle: isShowingDetail.toggle()
            case .dismiss: isShowingDetail = false
            case nil: break
            }
        }
        .onTapGesture {
            guard isShowingDetail else {
                guard Date().timeIntervalSince(lastDismissAt) > 0.3 else { return }
                isShowingDetail = true
                return
            }
            isShowingDetail = false
        }
        .popover(isPresented: $isShowingDetail, arrowEdge: .trailing) {
            EventDetailPopoverView(event: event, date: date)
        }
        .eventContextMenu(for: event)
    }

    @ViewBuilder
    private var timeDetailLine: some View {
        if let preview = previewRange {
            // While resizing: the times it will have.
            detailLine(icon: AppTheme.Symbol.time, text: "\(clock(preview.start)) – \(clock(preview.end))")
        } else {
            plainTimeDetailLine
        }
    }

    @ViewBuilder
    private var plainTimeDetailLine: some View {
        // Same "start – end" grammar as the plain case throughout — a
        // crossing event only ever gains date context on its endpoint
        // (or, on its final day, a "Since …" prefix), never an arrow or
        // a visually distinct notation.
        switch DayTimelineSegmentLabel.build(event: event, day: date, calendar: .autoupdatingCurrent, format: timeFormat) {
        case .sameDay, nil:
            if let range = event.rangeText(timeFormat) {
                detailLine(icon: AppTheme.Symbol.time, text: range)
            }
        case .startsHereEndsLater(let destination):
            if let start = event.startText(timeFormat) {
                detailLine(icon: AppTheme.Symbol.time, text: "\(start) – \(destination)")
            }
        case .continuesThroughDay:
            detailLine(icon: AppTheme.Symbol.time, text: L10n.tr("daytimelineeventview.continues", "Continues"))
        case .endsHere(let since, let until):
            detailLine(icon: AppTheme.Symbol.time, text: L10n.tr("daytimelineeventview.since", "Since \(String(describing: since)) – \(String(describing: until))"))
        }
    }

    private func detailLine(icon: String, text: String) -> some View {
        TimelineDetailLine(icon: icon, text: text, color: titleColor, isStruckThrough: isCancelled)
    }
}

/// Identifies the video service on an event block: the real bundled icon
/// for Zoom/Teams, a colored letter badge for anything else we can only
/// name (Meet), or a generic camera glyph as the last resort.
private struct VideoServiceBadge: View {
    @Environment(\.themePalette) private var theme

    let service: VideoConferenceService

    var body: some View {
        if let resourceName = service.iconResourceName {
            BrandIcon(resourceName: resourceName)
                .foregroundStyle(theme.primaryText)
                .frame(width: 15, height: 15)
        } else if let label = service.badgeLabel {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(theme.onAccentText)
                .frame(width: 11, height: 11)
                .background(Circle().fill(service.tintColor(theme: theme)))
        } else {
            Image(systemName: "video.fill")
                .font(.system(size: 9))
                .foregroundStyle(service.tintColor(theme: theme))
        }
    }
}

/// A diagonal-line hatch pattern in the given color — Apple Calendar's
/// classic "not yet accepted" texture, in place of a flat fill.
private struct DiagonalStripesBackground: View {
    @Environment(\.themePalette) private var theme
    let color: Color
    private let spacing: CGFloat = 6
    private let lineWidth: CGFloat = 1.2

    var body: some View {
        // A shape, not `Canvas`: each `Canvas` draw briefly allocated
        // ~130 MB of rendering buffers — for every tentative event shown.
        StripesShape(spacing: spacing)
            .stroke(color.opacity(theme.sourcePresentation.tentativeStripeOpacity), lineWidth: lineWidth)
            .saturation(theme.sourcePresentation.tentativeStripeSaturation)
    }
}

/// Parallel diagonal lines, bottom-left to top-right, `spacing` apart.
private struct StripesShape: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
