import SwiftUI
import Domain

package struct AgendaEventRowView: View {
    @Environment(\.themePalette) var theme

    @Environment(\.eventActionCoordinator) var eventActions
    @Environment(\.reminderSuppressionStore) var reminderSuppression
    @Environment(\.timeFormat) var timeFormat

    package let event: AgendaEventModel
    package let date: Date
    package var isKeyboardSelected = false
    package var isOngoing = false
    package var detailPresentationRequest: EventDetailPresentationRequest?
    package var detailActionRequest: EventDetailActionRequest?
    package var onDetailPresentationChange: (Bool) -> Void = { _ in }
    package var onDetailActionFocusChange: (EventDetailFocusableAction?) -> Void = { _ in }
    /// `.compact` in chat: one line, tighter.
    package var density: AgendaRowDensity = .regular
    /// Off where a container draws the row's selection (search results
    /// span a date tile too).
    package var drawsSelectionBackground = true
    /// Off where a container owns clicks (search: a click selects, Return
    /// opens the details).
    package var opensDetailsOnTap = true
    /// Off in the palette's search preview: no Join pill there.
    package var showsJoin = true
    /// Compact rows in search: the time and its glyphs get one fixed width,
    /// so every title starts at the same x (nil: as long as it is).
    package var compactTimeColumnWidth: CGFloat?
    /// Search: a long compact title fades out at the edge instead of "…".
    package var compactTitleFades = false

    @State var isHovering = false
    @State var isShowingDetail = false
    /// When the *same* click that's meant to close an open popover also
    /// lands on this row, the system's own outside-click dismissal (which
    /// runs on mouse-down, ahead of `onTapGesture`'s mouse-up recognition)
    /// has usually already flipped `isShowingDetail` to `false` by the
    /// time the tap gesture fires — so a plain `.toggle()` there reads
    /// "already closed" and immediately reopens it. Recording *when* a
    /// dismiss just happened lets the tap handler tell that apart from a
    /// genuinely later, separate click.
    @State private var lastDismissAt: Date = .distantPast

    private var isHighlighted: Bool { isShowingDetail || isKeyboardSelected || isHovering }

    /// The old `HStack(spacing: 6)` between glyphs, as text.
    static let glyphGap = Text("\u{2002}").font(.system(size: 10))

    var titleText: some View {
        Text(verbatim: event.title)
            .font(AppTheme.TextStyle.eventTitle.weight(event.status == .tentative ? .regular : .semibold))
            .foregroundStyle(titleColor)
            .strikethrough(event.status == .cancelled)
    }

    package var body: some View {
        HStack(alignment: .top, spacing: AppTheme.AgendaRow.markerToContent) {
            // Popover anchors here specifically (not the whole row) so its
            // pointer lines up exactly on the event, rather than floating
            // off the edge of a full-width row.
            AgendaLeadingMarkerSlot { statusIndicator }
                .accessibilityHidden(true)
                .popover(isPresented: $isShowingDetail, arrowEdge: .leading) {
                    EventDetailPopoverView(
                        event: event,
                        date: date,
                        actionRequest: detailActionRequest,
                        onActionFocusChange: onDetailActionFocusChange
                    )
                }

            if isOngoing {
                details
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(theme.content.ongoingIndicator)
                            .frame(width: 2)
                            .padding(.vertical, 2)
                    }
            } else {
                details
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, AppTheme.AgendaRow.leadingInset)
        .padding(.trailing, AppTheme.horizontalPadding)
        .padding(.vertical, density.verticalPadding)
        .background {
            // Inset with its own rounded rect rather than a full-bleed
            // fill, so the highlight reads as a card, not an edge-to-edge
            // bar. Only drawn when there is a highlight: most rows have none.
            if drawsSelectionBackground, isHighlighted {
                ThemedSurface(role: isKeyboardSelected ? .selection : .hover, fill: rowBackground,
                                shape: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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
            guard opensDetailsOnTap else { return }
            guard isShowingDetail else {
                // A click that lands right on the heels of the system's
                // own outside-click dismiss is that same click, not a new
                // one — ignore it so the row's "second click closes it"
                // behavior doesn't immediately reopen the popover.
                guard Date().timeIntervalSince(lastDismissAt) > 0.3 else { return }
                isShowingDetail = true
                return
            }
            isShowingDetail = false
        }
        .eventContextMenu(for: event)
    }

    package init(
        event: AgendaEventModel,
        date: Date,
        isKeyboardSelected: Bool = false,
        isOngoing: Bool = false,
        detailPresentationRequest: EventDetailPresentationRequest? = nil,
        detailActionRequest: EventDetailActionRequest? = nil,
        onDetailPresentationChange: @escaping (Bool) -> Void = { _ in },
        onDetailActionFocusChange: @escaping (EventDetailFocusableAction?) -> Void = { _ in },
        density: AgendaRowDensity = .regular,
        drawsSelectionBackground: Bool = true,
        opensDetailsOnTap: Bool = true,
        showsJoin: Bool = true,
        compactTimeColumnWidth: CGFloat? = nil,
        compactTitleFades: Bool = false
    ) {
        self.event = event
        self.date = date
        self.isKeyboardSelected = isKeyboardSelected
        self.isOngoing = isOngoing
        self.detailPresentationRequest = detailPresentationRequest
        self.detailActionRequest = detailActionRequest
        self.onDetailPresentationChange = onDetailPresentationChange
        self.onDetailActionFocusChange = onDetailActionFocusChange
        self.density = density
        self.drawsSelectionBackground = drawsSelectionBackground
        self.opensDetailsOnTap = opensDetailsOnTap
        self.showsJoin = showsJoin
        self.compactTimeColumnWidth = compactTimeColumnWidth
        self.compactTitleFades = compactTitleFades
    }
}

/// A tappable version of the plain video-service glyph the agenda row
/// already showed — same slot, but a small icon+"Join" pill (matching
/// `JoinCallButton`'s own "Join" pill styling, just scaled down and with
/// its brand icon folded in) that joins the call directly. Its tap takes
/// precedence over the row's `.onTapGesture`, so clicking anywhere else on
/// the row still opens the event detail popover as before.
///
/// Deliberately not a `Link` or `Button` (nor `.help`): a row is built
/// for every event the agenda keeps, and those controls measured about
/// 45 KB per pill (`.help` another 14 KB) — half a row's weight — for a
/// single click. A tap gesture with the same look, hover and button
/// semantics for VoiceOver costs almost nothing.
struct CompactJoinButton: View {
    @Environment(\.themePalette) private var theme
    let meetingLink: MeetingLink

    @State private var isHovering = false

    var body: some View {
        if let url = meetingLink.preferredURL {
            let tint = meetingLink.service.tintColor(theme: theme)
            HStack(spacing: 3) {
                iconView
                    .frame(width: 9, height: 9)
                Text(L10n.tr("agendaeventrowview.join", "Join"))
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isHovering ? theme.onAccentText : tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(isHovering ? tint : tint.opacity(theme.sourcePresentation.joinFillOpacity)))
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
            .onTapGesture { NSWorkspace.shared.open(url) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.tr("agendaeventrowview.join.09c8d1", "Join \(String(describing: meetingLink.service.displayName))"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { NSWorkspace.shared.open(url) }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let resourceName = meetingLink.service.iconResourceName {
            BrandIcon(resourceName: resourceName)
        } else {
            Image(systemName: "video.fill")
                .font(.system(size: 9))
        }
    }
}
