import AppKit
import SwiftUI
import Domain
import UI

/// The independent meeting slot. Its text changes without rendering a bitmap.
@MainActor
final class MenuBarMeetingItemController {
    var onCalendarClick: () -> Void = {}
    var onContextMenu: (NSStatusItem) -> Void = { _ in }
    private(set) var statusItem: NSStatusItem?
    private var onJoin: (() -> Void)?
    private let images = MenuBarImageCache<ImageKey>()

    private enum ImageKey: Equatable {
        case call(VideoConferenceService, CGFloat)
        case accent(Color, CGFloat)
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "\(Bundle.main.bundleIdentifier ?? "com.dayedge.app").status.meeting"
        item.isVisible = false
        if let button = item.button {
            button.imageScaling = .scaleNone
            button.imagePosition = .imageLeft
            button.imageHugsTitle = true
            button.font = AppTheme.MenuBar.meetingFont
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    func apply(_ presentation: MenuBarMeetingPresentation?, toolTip: String?, onJoin: (() -> Void)?) {
        self.onJoin = onJoin
        guard let item = statusItem, let button = item.button else { return }
        guard let presentation else {
            item.isVisible = false
            button.image = nil
            button.title = ""
            button.toolTip = nil
            return
        }
        let scale = button.window?.screen?.backingScaleFactor ?? 2
        let image: NSImage?
        let text: String
        switch presentation {
        case .callIcon(let service):
            text = ""
            image = images.image(for: .call(service, scale)) { CallJoinIcon.render(service: service, scale: scale) }
        case .contextual(let state, let configuration, let calendar, let timeFormat):
            text = state.label(configuration: configuration, calendar: calendar, format: timeFormat)
            if configuration.showsCalendarAccent, let event = state.event {
                image = images.image(for: .accent(event.color, scale)) { Self.accent(event.color, scale: scale) }
            } else {
                image = nil
            }
        }
        if button.image !== image { button.image = image }
        if button.title != text { button.title = text }
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip ?? text)
        item.isVisible = true
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

    @objc private func clicked() {
        guard let item = statusItem, let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            onContextMenu(item)
        } else if let onJoin {
            onJoin()
        } else {
            onCalendarClick()
        }
    }
}
