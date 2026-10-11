import AppKit
import Domain
import UI

@MainActor
final class MenuBarPrimaryRenderer {
    struct Content {
        let image: NSImage?
        let title: NSAttributedString
        let text: String
        let badgeWidth: CGFloat
        let hasCallIcon: Bool
    }

    private struct CombinedKey: Equatable {
        let badge: MenuBarBadgeImageKey
        let service: VideoConferenceService
    }

    private let badges = MenuBarImageCache<MenuBarBadgeImageKey>()
    private let combined = MenuBarImageCache<CombinedKey>()
    private let meetings = MenuBarMeetingRenderer()

    func render(_ presentation: MenuBarPrimaryPresentation, scale: CGFloat) -> Content {
        let key = MenuBarBadgeImageKey(number: presentation.badge.number, glyph: presentation.cornerGlyph, scale: scale)
        let badge = presentation.showsIcon ? badges.image(for: key) {
            MenuBarBadgeIcon.render(value: key.number, cornerGlyph: key.glyph, scale: scale)
        } : nil
        switch presentation.meeting {
        case .callIcon(let service):
            let call = meetings.render(.callIcon(service), scale: scale).image
            let image = combined.image(for: CombinedKey(badge: key, service: service)) {
                guard let badge, let call else { return nil }
                return Self.combine(badge, call, scale: scale)
            }
            return Content(image: image, title: title("", font: AppTheme.MenuBar.meetingFont), text: "",
                           badgeWidth: badge?.size.width ?? 0, hasCallIcon: true)
        case .contextual(let state, let configuration, let calendar, let timeFormat):
            let meeting = meetings.render(.contextual(state: state, configuration: configuration,
                                                       calendar: calendar, timeFormat: timeFormat), scale: scale)
            let label = NSMutableAttributedString(string: "")
            if let accent = meeting.image {
                let attachment = NSTextAttachment()
                attachment.image = accent
                let font = AppTheme.MenuBar.meetingFont
                attachment.bounds = CGRect(x: 0, y: (font.ascender + font.descender - accent.size.height) / 2,
                                           width: accent.size.width, height: accent.size.height)
                label.append(NSAttributedString(attachment: attachment))
            }
            label.append(title(meeting.text, font: AppTheme.MenuBar.meetingFont))
            return Content(image: badge, title: label, text: meeting.text,
                           badgeWidth: badge?.size.width ?? 0, hasCallIcon: false)
        case nil:
            return Content(image: badge, title: title(presentation.text, font: AppTheme.MenuBar.primaryFont),
                           text: presentation.text, badgeWidth: badge?.size.width ?? 0, hasCallIcon: false)
        }
    }

    private func title(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
    }

    private static func combine(_ badge: NSImage, _ call: NSImage, scale: CGFloat) -> NSImage? {
        let size = NSSize(width: badge.size.width + 2 + call.size.width, height: max(badge.size.height, call.size.height))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * scale)), pixelsHigh: Int(ceil(size.height * scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        badge.draw(in: NSRect(x: 0, y: (size.height - badge.size.height) / 2, width: badge.size.width, height: badge.size.height))
        call.draw(in: NSRect(x: badge.size.width + 2, y: (size.height - call.size.height) / 2,
                             width: call.size.width, height: call.size.height))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}
