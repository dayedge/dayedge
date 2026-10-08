import SwiftUI
import Domain

extension AgendaEventRowView {
    /// `nil` when the event has no real `startDate`/`endDate` (mock/legacy
    /// data) — the row falls back to its plain "HH:mm – HH:mm" rendering
    /// in that case, exactly as before this event ever had day-relative
    /// wording.
    private var timeMetadataLabel: AgendaTimeMetadataLabel? {
        AgendaTimeMetadataLabel.build(event: event, day: date, calendar: .autoupdatingCurrent, format: timeFormat)
    }

    /// The time and the event's glyphs (join, link, repeat, muted). The
    /// time and plain symbol glyphs are one `Text` (fewer views per row —
    /// rows are built as they scroll in); only the interactive Join pill,
    /// the brand icon and the muted bell are views beside it.
    @ViewBuilder
    var timeLine: some View {
        // A meeting that's over has nothing to join: its service shows as
        // the plain brand icon instead of the pill.
        let isOver = (event.endDate ?? event.startDate).map { $0 <= Date() } ?? false
        let joinLink = isOver ? nil : event.meetingLink.flatMap { $0.canJoin ? $0 : nil }
        let brand = joinLink == nil ? event.videoService?.iconResourceName : nil
        let isMuted = reminderSuppression?.isMuted(event) == true
        if (joinLink == nil || !showsJoin) && brand == nil && !isMuted {
            // The common shape: everything is text.
            timeGlyphs(includingVideo: joinLink == nil, trailing: true)
        } else {
            HStack(spacing: 6) {
                timeGlyphs(includingVideo: joinLink == nil && brand == nil, trailing: false)
                if let joinLink {
                    if showsJoin { CompactJoinButton(meetingLink: joinLink) }
                } else if let brand {
                    BrandIcon(resourceName: brand)
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 14, height: 14)
                }
                if event.hasLinkIcon || event.isRecurring { trailingGlyphs }
                if isMuted {
                    Button {
                        eventActions?.restoreReminders(for: event)
                    } label: {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverTooltip(L10n.tr("agendaeventrowview.time.restore.reminders", "Restore Reminders"))
                    .accessibilityLabel(L10n.tr("agendaeventrowview.time.reminders.muted", "Reminders muted"))
                    .accessibilityHint(L10n.tr("agendaeventrowview.time.activate.to.restore.reminders", "Activate to restore reminders."))
                }
            }
        }
    }

    /// "10:30 – 11:45" with the video glyph and — when nothing sits between
    /// them — the link and repeat glyphs, as one `Text`.
    private func timeGlyphs(includingVideo: Bool, trailing: Bool) -> Text {
        var text = timeMetadataString
            .map { Text($0).font(AppTheme.TextStyle.eventTime).foregroundStyle(timeColor).strikethrough(event.status == .cancelled) }
            ?? Text("")
        if includingVideo, let videoService = event.videoService, videoService.iconResourceName == nil {
            text = Text("\(text)\(Self.glyphGap)\(Text(Image(systemName: "video.fill")).font(.system(size: 10)).foregroundStyle(videoService.tintColor(theme: theme)))")
        }
        if trailing {
            if event.hasLinkIcon { text = Text("\(text)\(Self.glyphGap)\(glyph("link"))") }
            if event.isRecurring { text = Text("\(text)\(Self.glyphGap)\(glyph("repeat"))") }
        }
        return text
    }

    /// The link and repeat glyphs after a Join pill or brand icon.
    private var trailingGlyphs: Text {
        let glyphs = [event.hasLinkIcon ? glyph("link") : nil, event.isRecurring ? glyph("repeat") : nil].compactMap { $0 }
        return glyphs.dropFirst().reduce(glyphs.first ?? Text("")) { Text("\($0)\(Self.glyphGap)\($1)") }
    }

    private func glyph(_ name: String) -> Text {
        Text(Image(systemName: name)).font(.system(size: 10)).foregroundStyle(theme.secondaryText)
    }

    private var timeMetadataString: String? {
        if let timeMetadataLabel { return timeMetadataLabel.displayText }
        if let range = event.rangeText(timeFormat) { return range }
        return nil
    }
}
