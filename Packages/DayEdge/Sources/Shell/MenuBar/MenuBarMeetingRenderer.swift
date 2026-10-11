import AppKit
import SwiftUI
import Domain

/// Shared meeting assets; changing text never invalidates the image cache.
@MainActor
final class MenuBarMeetingRenderer {
    struct Content {
        let image: NSImage?
        let text: String
    }

    private enum ImageKey: Equatable {
        case call(VideoConferenceService, CGFloat)
        case accent(Color, CGFloat)
    }

    private let images = MenuBarImageCache<ImageKey>()

    func render(_ presentation: MenuBarMeetingPresentation, scale: CGFloat) -> Content {
        switch presentation {
        case .callIcon(let service):
            return Content(
                image: images.image(for: .call(service, scale)) { CallJoinIcon.render(service: service, scale: scale) },
                text: ""
            )
        case .contextual(let state, let configuration, let calendar, let timeFormat):
            let text = state.label(configuration: configuration, calendar: calendar, format: timeFormat)
            let image = configuration.showsCalendarAccent ? state.event.flatMap { event in
                images.image(for: .accent(event.color, scale)) { Self.accent(event.color, scale: scale) }
            } : nil
            return Content(image: image, text: text)
        }
    }

    private static func accent(_ color: Color, scale: CGFloat) -> NSImage {
        let size = NSSize(width: 5, height: 18)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(color).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 2, width: 2, height: 14), xRadius: 1, yRadius: 1).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

}
