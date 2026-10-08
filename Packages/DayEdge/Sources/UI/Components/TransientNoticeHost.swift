import AppKit
import SwiftUI
import Domain

/// Lives inside the calendar window, above its content. It never takes focus
/// when shown; only the optional action participates in keyboard navigation.
package struct TransientNoticeHost: View {
    @Environment(\.themePalette) private var theme

    package let center: NoticeCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer(minLength: 0)
                if let notice = center.currentNotice {
                    noticeView(notice)
                        .frame(maxWidth: BottomSurface.width(in: geometry.size.width))
                        .transition(BottomSurface.transition(reduceMotion: reduceMotion))
                        .onHover { center.setHovering($0, for: notice.id) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, BottomSurface.bottomPadding)
            .animation(BottomSurface.animation(appearing: center.currentNotice != nil), value: center.currentNotice?.id)
            .onChange(of: center.currentNotice?.id) { _, id in
                guard let id, let notice = center.currentNotice, notice.id == id else { return }
                NSAccessibility.post(
                    element: NSApplication.shared,
                    notification: .announcementRequested,
                    userInfo: [.announcement: notice.accessibilityAnnouncement,
                               .priority: NSAccessibilityPriorityLevel.medium.rawValue]
                )
            }
        }
    }

    private func noticeView(_ notice: TransientNotice) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: notice.style.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(notice.style.iconColor(theme: theme))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(AppTheme.TextStyle.eventTitle)
                    .foregroundStyle(theme.primaryText)
                if let message = notice.message {
                    Text(message)
                        .font(AppTheme.TextStyle.eventSubtitle)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if let action = notice.action {
                Spacer(minLength: 4)
                Button(action.title) { center.performAction(for: notice.id) }
                    .font(AppTheme.TextStyle.eventTitle)
                    .foregroundStyle(theme.nativeControlAccent)
                    .buttonStyle(.plain)
                    .accessibilityHint(L10n.tr("transientnoticehost.activates.for.this.notice", "Activates \(String(describing: action.title)) for this notice"))
            }
        }
        .padding(.horizontal, BottomSurface.contentPaddingH)
        .padding(.vertical, notice.message == nil ? 11 : 12)
        .frame(minHeight: notice.message == nil ? 42 : 60)
        .bottomSurface()
        .accessibilityElement(children: .contain)
    }
}

private extension NoticeStyle {
    var symbolName: String {
        switch self {
        case .information: "clock"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.circle"
        }
    }

    func iconColor(theme: ThemePalette) -> Color {
        switch self {
        case .information: theme.secondaryText
        case .success: theme.successGreen
        case .warning: theme.dotOrange
        case .error: theme.accentRed
        }
    }
}

#if HAS_MACOS26_SDK
#Preview(L10n.tr("transientnoticehost.information", "Information")) {
    NoticePreview(.information(title: L10n.tr("transientnoticehost.no.previous.occurrence.found", "No previous occurrence found")))
}

#Preview(L10n.tr("transientnoticehost.two.lines", "Two lines")) {
    NoticePreview(.information(title: L10n.tr(
        "transientnoticehost.no.previous.occurrence", "No previous occurrence"
    ), message: L10n.tr(
        "transientnoticehost.none.found.within.4.years", "None found within 4 years."
    )))
}

#Preview(L10n.tr("transientnoticehost.undo", "Undo")) {
    NoticePreview(.success(title: L10n.tr(
        "transientnoticehost.cancelled.event.removed", "Cancelled event removed"
    ), action: NoticeAction(title: L10n.tr(
        "transientnoticehost.undo", "Undo"
    ), handler: {})))
}

#Preview(L10n.tr("transientnoticehost.error.and.long.text", "Error and long text")) {
    NoticePreview(.error(title: L10n.tr(
        "transientnoticehost.couldn.t.open.the.meeting.307714", "Couldn’t open the meeting link for this event"
    ), message: L10n.tr(
        "transientnoticehost.please.check.the.link.in.your.calendar", "Please check the link in your calendar."
    )))
}

#Preview(L10n.tr("transientnoticehost.light.appearance", "Light appearance")) {
    NoticePreview(.information(title: L10n.tr("transientnoticehost.no.matching.events.found", "No matching events found")))
        .environment(\.themePalette, ThemePalette.appleLight)
        .preferredColorScheme(.light)
}

private struct NoticePreview: View {
    @Environment(\.themePalette) private var theme

    let center = NoticeCenter()
    let notice: TransientNotice

    init(_ notice: TransientNotice) { self.notice = notice }

    var body: some View {
        Color.clear
            .frame(width: 320, height: 180)
            .themedSurface(.elevated, fill: theme.background, in: Rectangle())
            .overlay { TransientNoticeHost(center: center) }
            .task {
                center.show(TransientNotice(
                    style: notice.style, title: notice.title, message: notice.message,
                    action: notice.action, duration: 3600
                ))
            }
    }
}
#endif
