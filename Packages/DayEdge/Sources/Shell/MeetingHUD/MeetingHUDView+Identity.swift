import AppKit
import Observation
import SwiftUI
import UI

extension MeetingHUDView {
    // MARK: - Left: identity + timing

    var leftGroup: some View {
        HStack(alignment: .top, spacing: 9) {
            CalendarColorDot(occurrence: occurrence)
                // Aligns with the title's cap-height rather than
                // spanning/centering across both text rows.
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                titleRow
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    timeRow(at: context.date)
                }
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Button(action: toggleEventDetail) {
                Text(occurrence.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText.opacity(isTitleHovered ? 1 : 0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focusedControl, equals: .title)
            .hoverTooltip(isPresented: isTitleHovered && !isShowingEventDetail, edge: .top) {
                TooltipLabel(text: L10n.tr("meetinghudview.identity.show.event", "Show Event"))
            }
            .accessibilityLabel(L10n.tr("meetinghudview.identity.show.details.for", "Show details for \(String(describing: occurrence.title))"))
            .accessibilityValue(isShowingEventDetail ? L10n.tr("meetinghudview.identity.open", "Open") : L10n.tr("meetinghudview.identity.closed", "Closed"))
            .onHover { hovering in
                if hovering != isTitleHovered {
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                isTitleHovered = hovering
            }
            .onDisappear {
                if isTitleHovered { NSCursor.pop(); isTitleHovered = false }
            }
            .contextMenu {
                resetPositionMenuItem
            }
            .popover(
                isPresented: $isShowingEventDetail,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                EventDetailPopoverView(event: occurrence.event, date: occurrence.start)
            }
            .onChange(of: isShowingEventDetail) { wasShowing, isShowing in
                if wasShowing, !isShowing {
                    lastEventDetailDismissAt = .now
                }
            }
            .onChange(of: occurrence.id) { _, _ in
                isShowingEventDetail = false
            }

            if let count = occurrence.participantCount {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                    Text("\(count)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                }
                .foregroundStyle(theme.secondaryText)
                // Never compressed — the title is what truncates to make
                // room for this, not the other way around.
                .fixedSize()
                .layoutPriority(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(count) participants")
            }
        }
    }

    func toggleEventDetail() {
        if isShowingEventDetail {
            isShowingEventDetail = false
            return
        }
        // A popover dismisses on mouse-down; do not immediately reopen it
        // from the matching mouse-up on the title.
        guard Date.now.timeIntervalSince(lastEventDetailDismissAt) > 0.3 else { return }
        isShowingEventDetail = true
    }

    private func timeRow(at now: Date) -> some View {
        HStack(spacing: 0) {
            Text(exactTimeString)
                .foregroundStyle(theme.secondaryText)
            Text(" · ")
                .foregroundStyle(theme.dimmedText)
            // One level brighter than the exact time — explains why the
            // HUD is on-screen, so it gets slightly more visual weight,
            // deliberately without alarm coloring (no red/orange).
            Text(relativeStatus(at: now))
                .foregroundStyle(theme.primaryText.opacity(0.78))
                .fontWeight(.medium)
        }
        .font(.system(size: 12.5).monospacedDigit())
        .fixedSize()
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
    }

    private var exactTimeString: String {
        timeFormat.range(occurrence.start, occurrence.end)
    }

    /// Mirrors `MenuBarEventIndicatorResolver`'s existing rounding
    /// convention (ceiling minutes remaining, floor minutes elapsed)
    /// rather than deriving separate rules for the HUD.
    private func relativeStatus(at now: Date) -> String {
        let secondsUntilStart = occurrence.start.timeIntervalSince(now)
        if secondsUntilStart > 0 {
            let minutes = max(1, Int((secondsUntilStart / 60).rounded(.up)))
            return "in \(minutes) min"
        }
        let minutesElapsed = Int((-secondsUntilStart / 60).rounded(.down))
        guard minutesElapsed > 0 else { return L10n.tr("meetinghudview.identity.starting.now", "starting now") }
        return L10n.tr("meetinghudview.identity.started.min.ago", "started \(String(describing: minutesElapsed)) min ago")
    }
}
