import AppKit
import SwiftUI
import XCTest
@testable import Shell
@testable import Domain
@testable import UI

/// Opt-in visual fixtures use real presentation components and isolated settings.
/// No Calendar/Reminders access or changes to the user's running app.
@MainActor
final class LocalizationLayoutTests: XCTestCase {
    func testLocalizationLayoutPreviews() throws {
        guard let path = ProcessInfo.processInfo.environment["DAYEDGE_LOCALIZATION_PREVIEWS_DIR"] else {
            throw XCTSkip("Set DAYEDGE_LOCALIZATION_PREVIEWS_DIR to export English, expanded, and RTL layouts")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "LocalizationLayout-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let appearance = AppearanceStore(defaults: defaults, observesSystem: false)
        try render(OnboardingWelcomeStep(), appearance: appearance, size: NSSize(width: 648, height: 360),
                   to: directory.appendingPathComponent("onboarding-en.png"))
        let expanded = try text("fixture.expanded", language: "pl")
        try render(settings(title: expanded, subtitle: expanded), appearance: appearance, size: NSSize(width: 360, height: 280),
                   to: directory.appendingPathComponent("settings-expanded.png"))
        try render(pickerSettings, appearance: appearance, size: NSSize(width: 420, height: 180),
                   to: directory.appendingPathComponent("settings-polish-picker.png"))
        let rtl = try text("fixture.rtl", language: "ar")
        try render(settings(title: rtl, subtitle: rtl).environment(\.layoutDirection, .rightToLeft),
                   appearance: appearance, size: NSSize(width: 360, height: 280),
                   to: directory.appendingPathComponent("settings-rtl.png"))
    }

    private func text(_ key: String, language: String) throws -> String {
        let path = try XCTUnwrap(Bundle.module.path(forResource: language, ofType: "lproj", inDirectory: "Localization"))
        return try XCTUnwrap(Bundle(path: path)).localizedString(forKey: key, value: nil, table: nil)
    }

    private var pickerSettings: some View {
        SettingsGroup(header: "Dni robocze") {
            SettingsPickerRow(title: "Region świąt", selection: .constant("auto"), options: [
                ("auto", "Automatycznie (Polska)"),
                ("long", "Dalekie Wyspy Mniejsze Stanów Zjednoczonych")
            ])
            SettingsPickerRow(title: "Tydzień pracy", selection: .constant("auto"), options: [
                ("auto", "Automatycznie"), ("week", "Od poniedziałku do piątku")
            ])
        }
        .padding(16)
    }

    private func settings(title: String, subtitle: String) -> some View {
        SettingsGroup(header: title, footer: subtitle) {
            SettingsRow(title: title, subtitle: subtitle) { Text(verbatim: "Calendar 10:30") }
        }
        .padding(16)
    }

    private func render<Content: View>(_ content: Content, appearance: AppearanceStore, size: NSSize, to url: URL) throws {
        let host = NSHostingView(rootView: ThemedRoot(content: content, appearance: appearance))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.frame = NSRect(origin: .zero, size: size)
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
        }
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        XCTAssertGreaterThan(image.pixelsWide, 0)
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
    }
}
