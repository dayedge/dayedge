import AppKit

/// One retained image per independently changing icon; text never enters its key.
@MainActor
final class MenuBarImageCache<Key: Equatable> {
    private var last: (key: Key, image: NSImage)?

    func image(for key: Key, draw: () -> NSImage?) -> NSImage? {
        if let last, last.key == key { return last.image }
        guard let image = draw() else { return nil }
        last = (key, image)
        return image
    }
}

struct MenuBarBadgeImageKey: Equatable {
    let number: Int
    let glyph: MenuBarCornerGlyph?
    let scale: CGFloat
}
