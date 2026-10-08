import SwiftUI
import XCTest
@testable import Intelligence
@testable import UI

/// Temporary guard for the palette refactor: writes every theme's tokens to
/// DAYEDGE_PALETTE_DUMP so a before/after diff shows any change.
final class PaletteTokenDumpTests: XCTestCase {
    @MainActor
    func testDumpPaletteTokens() throws {
        guard let path = ProcessInfo.processInfo.environment["DAYEDGE_PALETTE_DUMP"] else { throw XCTSkip("set DAYEDGE_PALETTE_DUMP") }
        var out = ""
        func dump(_ value: Any, _ prefix: String) {
            let mirror = Mirror(reflecting: value)
            if mirror.children.isEmpty || value is Color {
                out += "\(prefix) = \(String(describing: value))\n"
                return
            }
            for child in mirror.children { dump(child.value, prefix + "." + (child.label ?? "?")) }
        }
        let named: [(String, ThemePalette)] = [("opal", .opal), ("appleLight", .appleLight), ("appleDark", .appleDark),
                                               ("appleSystemLight", .appleSystemLight), ("appleSystemDark", .appleSystemDark)]
        for (name, palette) in named { dump(palette.values, name) }
        for theme in ThemeCatalog.themes {
            for scheme in [ColorScheme.light, .dark] { dump(theme.palette(scheme).values, "\(theme.id)-\(scheme)") }
        }
        try out.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// The same for the assistant's prompts, at a fixed moment.
    func testDumpAssistantInstructions() throws {
        guard let path = ProcessInfo.processInfo.environment["DAYEDGE_PROMPT_DUMP"] else { throw XCTSkip("set DAYEDGE_PROMPT_DUMP") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let text = AssistantInstructions.full(now: now, calendar: calendar) + "\n----\n" + AssistantInstructions.onDevice(now: now, calendar: calendar)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
