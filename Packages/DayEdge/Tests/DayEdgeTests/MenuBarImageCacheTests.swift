import AppKit
import XCTest
@testable import Shell

@MainActor
final class MenuBarImageCacheTests: XCTestCase {
    func testMinuteTextChangesReuseBadgeImage() {
        let cache = MenuBarImageCache<MenuBarBadgeImageKey>()
        let key = MenuBarBadgeImageKey(number: 11, glyph: nil, scale: 2)
        var renders = 0
        let first = cache.image(for: key) { renders += 1; return NSImage(size: NSSize(width: 22, height: 22)) }
        let nextMinute = cache.image(for: key) { renders += 1; return NSImage() }
        XCTAssertTrue(first === nextMinute)
        XCTAssertEqual(renders, 1)
    }

    func testChangedGlyphDrawsNewImage() {
        let cache = MenuBarImageCache<MenuBarBadgeImageKey>()
        let first = cache.image(for: MenuBarBadgeImageKey(number: 11, glyph: nil, scale: 2)) { NSImage() }
        let changed = cache.image(for: MenuBarBadgeImageKey(number: 11, glyph: .tasksDue, scale: 2)) { NSImage() }
        XCTAssertFalse(first === changed)
    }

    func testChangedDisplayScaleDrawsNewImage() {
        let cache = MenuBarImageCache<MenuBarBadgeImageKey>()
        let first = cache.image(for: MenuBarBadgeImageKey(number: 11, glyph: nil, scale: 1)) { NSImage() }
        let changed = cache.image(for: MenuBarBadgeImageKey(number: 11, glyph: nil, scale: 2)) { NSImage() }
        XCTAssertFalse(first === changed)
    }
}
