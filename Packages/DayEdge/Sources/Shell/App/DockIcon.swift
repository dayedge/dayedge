import AppKit
import Domain

/// The running app's Dock icon: the clean calendar artwork
/// (`Resources/DockIconBase.png`) with today's month and year drawn on it,
/// the way the fixed app icon (`Assets/AppIcon-1024.png`, Finder and
/// Applications) shows "JAN 2026" — so the Dock always shows the current
/// month. Redrawn when the day changes and after wake — only while the app
/// is in the Dock (`setShown`); otherwise the bundle's icon stands.
///
/// Drawn once with AppKit into a fixed bitmap the artwork's size. Not
/// SwiftUI's `ImageRenderer` (~130 MB of rendering buffers per image), and
/// not a drawing-handler `NSImage`: AppKit renders one of those at screen
/// scale in 16-bit channels, twice, and keeps both — 64 MB for a 1024-point
/// icon.
@MainActor
final class DockIcon {
    static let shared = DockIcon()

    private var observers: [NSObjectProtocol] = []
    private var shownMonth: DateComponents?

    /// The dated icon while the app is in the Dock; the bundle's own icon
    /// (and no image held) while it isn't.
    func setShown(_ shown: Bool) {
        if shown { start() } else { stop() }
    }

    /// Sets the icon and keeps it current.
    private func start() {
        update()
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { _ in Task { @MainActor in DockIcon.shared.update() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in DockIcon.shared.update() } })
    }

    private func stop() {
        guard !observers.isEmpty || shownMonth != nil else { return }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        shownMonth = nil
        NSApp.applicationIconImage = nil
    }

    /// Redraws only when the month changed.
    func update(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        let month = calendar.dateComponents([.year, .month], from: now)
        guard month != shownMonth, let image = Self.image(for: now, calendar: calendar) else { return }
        shownMonth = month
        NSApp.applicationIconImage = image
    }

    /// The artwork with `date`'s month and year. Positions and sizes are
    /// the dated icon's, measured on its 1254-pixel design: the month's
    /// capitals from y 357 down to the baseline at 429 starting at x 293,
    /// the year 40 px after it on the same baseline, its capitals from 373.
    static func image(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> NSImage? {
        guard let url = Bundle.module.url(forResource: "DockIconBase", withExtension: "png"),
              let base = NSImage(contentsOf: url) else { return nil }
        let month = DatePresentationFormatter.current.with(calendar).month(date, abbreviated: true).uppercased()
        let year = String(calendar.component(.year, from: date))

        // The artwork's own pixels, 8 bits a channel: nothing for AppKit to
        // re-render larger.
        let pixels = 512
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)

        NSGraphicsContext.saveGraphicsState()
        // Top-down, as the design is measured.
        context.cgContext.translateBy(x: 0, y: rect.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        do {
            base.draw(in: rect)
            let scale = rect.width / 1254
            let baseline = 429 * scale
            // Cap height ≈ 0.705 em in SF Pro: 72 px capitals → 102 px type.
            let monthFont = NSFont.systemFont(ofSize: 102 * scale, weight: .semibold, width: NSFont.Width(rawValue: 0.1))
            let yearFont = NSFont.systemFont(ofSize: 78 * scale, weight: .regular)
            let monthText = NSAttributedString(string: month, attributes: [
                .font: monthFont, .foregroundColor: NSColor.white, .kern: 1.5 * scale
            ])
            let yearText = NSAttributedString(string: year, attributes: [
                .font: yearFont,
                .foregroundColor: NSColor(srgbRed: 0.77, green: 0.79, blue: 0.84, alpha: 1)
            ])
            // `draw(at:)` in a flipped context places the line's top; the
            // baseline is an ascender below it.
            let monthOrigin = NSPoint(x: 293 * scale, y: baseline - monthFont.ascender)
            monthText.draw(at: monthOrigin)
            let yearX = monthOrigin.x + monthText.size().width + 28 * scale
            yearText.draw(at: NSPoint(x: yearX, y: baseline - yearFont.ascender))
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmap)
        return image
    }
}
