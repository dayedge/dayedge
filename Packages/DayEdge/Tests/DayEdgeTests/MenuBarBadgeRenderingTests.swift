import AppKit
import SwiftUI
import XCTest
@testable import Shell

@MainActor
final class MenuBarBadgeRenderingTests: XCTestCase {
    func testTwoDigitDateRendersDifferentlyFromNine() throws {
        let date = try render(MenuBarBadgeIcon(value: 31))
        let nine = try render(MenuBarBadgeIcon(value: 9))
        XCTAssertNotEqual(png(date), png(nine))
    }

    func testTwoDigitsKeepTheSameCanvasSize() throws {
        let date = try render(MenuBarBadgeIcon(value: 31))
        let singleDigit = try render(MenuBarBadgeIcon(value: 1))
        XCTAssertEqual(date.width, singleDigit.width)
        XCTAssertEqual(date.height, singleDigit.height)
    }

    func testBadgePreviews() throws {
        guard let path = ProcessInfo.processInfo.environment["DAYEDGE_BADGE_PREVIEWS_DIR"] else {
            throw XCTSkip("Set DAYEDGE_BADGE_PREVIEWS_DIR to export badge previews")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preview = VStack(spacing: 12) {
            badges(ink: .black).padding(12).background(Color.white)
            badges(ink: .white).padding(12).background(Color.black)
        }
        for scale: CGFloat in [1, 2, 8] {
            let image = try render(preview, scale: scale)
            try XCTUnwrap(png(image)).write(to: directory.appendingPathComponent("badges-\(Int(scale))x.png"))
        }
    }

    private func badges(ink: Color) -> some View {
        HStack(spacing: 12) {
            MenuBarBadgeIcon(value: 0, inkColor: ink)
            MenuBarBadgeIcon(value: 9, cornerGlyph: .overflow, inkColor: ink)
            MenuBarBadgeIcon(value: 1, inkColor: ink)
            MenuBarBadgeIcon(value: 10, inkColor: ink)
            MenuBarBadgeIcon(value: 11, inkColor: ink)
            MenuBarBadgeIcon(value: 28, inkColor: ink)
            MenuBarBadgeIcon(value: 31, inkColor: ink)
            MenuBarBadgeIcon(value: 31, cornerGlyph: .tasksDue, inkColor: ink)
            MenuBarBadgeIcon(value: 9, cornerGlyph: .tasksDue, inkColor: ink)
        }
    }

    private func render<Content: View>(_ content: Content, scale: CGFloat = 2) throws -> CGImage {
        let renderer = ImageRenderer(content: content.environment(\.locale, Locale(identifier: "en_US_POSIX")))
        renderer.scale = scale
        return try XCTUnwrap(renderer.cgImage)
    }

    private func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
