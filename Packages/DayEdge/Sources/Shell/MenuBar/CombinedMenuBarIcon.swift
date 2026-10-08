import AppKit
import SwiftUI
import Domain

enum MenuBarAccessory: Equatable {
    case callIcon(VideoConferenceService)
    case contextual(
        state: MenuBarEventIndicatorState,
        configuration: MenuBarEventIndicatorConfiguration,
        calendar: Calendar,
        timeFormat: TimeFormat
    )
}

/// Keeps the app in one menu-bar slot. The calendar is always the stable
/// left-hand anchor; the mutually exclusive meeting icon or contextual
/// event text appears to its right.
struct CombinedMenuBarIcon: View {
    let accessory: MenuBarAccessory?
    let badgeValue: Int
    let cornerBadge: MenuBarCornerBadge?

    // The badge canvas reserves transparent room for its corner badge.
    // Slight negative spacing makes the next visible element sit at a
    // normal optical distance from the calendar outline.
    static let iconSpacing: CGFloat = -1
    // Contextual rendering cannot be a system template because it may
    // include a calendar-color accent. Use explicit menu-bar ink so an
    // off-screen ImageRenderer does not resolve `.labelColor` as black.
    private let ink = Color.white.opacity(0.92)

    var body: some View {
        HStack(spacing: Self.iconSpacing) {
            MenuBarBadgeIcon(value: badgeValue, cornerBadge: cornerBadge, inkColor: ink)
                .offset(y: -2)

            switch accessory {
            case .callIcon(let service):
                CallJoinIcon(service: service, inkColor: ink)
            case .contextual(let state, let configuration, let calendar, let timeFormat):
                MenuBarContextualEventView(
                    state: state,
                    configuration: configuration,
                    calendar: calendar,
                    timeFormat: timeFormat,
                    ink: ink
                )
            case nil:
                EmptyView()
            }
        }
    }
}

private struct MenuBarContextualEventView: View {
    let state: MenuBarEventIndicatorState
    let configuration: MenuBarEventIndicatorConfiguration
    let calendar: Calendar
    let timeFormat: TimeFormat
    let ink: Color

    var body: some View {
        HStack(spacing: 3) {
            if configuration.showsCalendarAccent, let event = state.event {
                RoundedRectangle(cornerRadius: 1)
                    .fill(event.color)
                    .frame(width: 2, height: 14)
            }

            compactLabel
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink)
        }
        .frame(height: MenuBarBadgeIcon.totalCanvasHeight)
    }

    @ViewBuilder
    private var compactLabel: some View {
        switch state {
        case .free(let until):
            Text(L10n.tr("combinedmenubaricon.free.until", "Free until \(String(describing: formattedTime(until)))"))
                .fixedSize(horizontal: true, vertical: false)

        case .upcoming(let event, let minutes):
            eventLabel(status: "\(minutes)m", event: event)

        case .ongoing(let event, let remaining):
            eventLabel(status: remaining.map { L10n.tr("combinedmenubaricon.m.left", "\(String(describing: $0))m left") } ?? "NOW", event: event)
        }
    }

    private func eventLabel(status: String, event: AgendaEventModel) -> some View {
        HStack(spacing: 3) {
            Text(status)
                .fixedSize(horizontal: true, vertical: false)

            if configuration.showsEventTitle, !event.title.isEmpty {
                separator
                Text(compactTitle(event.title))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if configuration.showsEventEndTime, let endTime = event.endText(timeFormat, calendar: calendar) {
                Text("→\(endTime)")
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(ink)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(ink.opacity(0.55))
    }

    private func formattedTime(_ date: Date) -> String {
        timeFormat.time(date, calendar: calendar)
    }

    private func compactTitle(_ title: String) -> String {
        let limit = 13
        guard title.count > limit else { return title }
        return String(title.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

extension CombinedMenuBarIcon {
    struct Rendered {
        let image: NSImage
        /// Button-local x coordinate at which the right-hand accessory
        /// begins. AppDelegate only treats it as an action when the
        /// represented event has a joinable call.
        let accessoryRegionMinX: CGFloat?
    }

    /// What an icon is drawn from; the same key draws the same icon.
    private struct Key: Equatable {
        let accessory: MenuBarAccessory?
        let badgeValue: Int
        let cornerBadge: MenuBarCornerBadge?
        let scale: CGFloat
    }

    @MainActor private static var last: (key: Key, rendered: Rendered)?

    /// The icon for these inputs — drawn only when they changed. The menu
    /// bar refreshes every minute (and on activation, wake, every task or
    /// calendar change), and most refreshes ask for the very icon it
    /// already shows; each `ImageRenderer` pass briefly costs ~130 MB of
    /// graphics memory for a 22-point image.
    @MainActor
    static func render(accessory: MenuBarAccessory?, badgeValue: Int, cornerBadge: MenuBarCornerBadge?) -> Rendered? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let key = Key(accessory: accessory, badgeValue: badgeValue, cornerBadge: cornerBadge, scale: scale)
        if let last, last.key == key { return last.rendered }
        guard let rendered = draw(accessory: accessory, badgeValue: badgeValue, cornerBadge: cornerBadge, scale: scale)
        else { return nil }
        last = (key, rendered)
        return rendered
    }

    @MainActor
    private static func draw(accessory: MenuBarAccessory?, badgeValue: Int, cornerBadge: MenuBarCornerBadge?,
                             scale: CGFloat) -> Rendered? {
        let renderer = ImageRenderer(content: CombinedMenuBarIcon(
            accessory: accessory, badgeValue: badgeValue, cornerBadge: cornerBadge
        ))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }

        // A calendar-color accent cannot be represented by a monochrome
        // template. Retain native menu-bar tinting for the compact layout.
        if case .contextual = accessory {
            image.isTemplate = false
        } else {
            image.isTemplate = true
        }

        let accessoryRegionMinX = accessory == nil
            ? nil
            : MenuBarBadgeIcon.totalCanvasWidth + iconSpacing / 2
        return Rendered(image: image, accessoryRegionMinX: accessoryRegionMinX)
    }
}
