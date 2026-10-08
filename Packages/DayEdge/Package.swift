// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Some newer SwiftUI APIs (the macOS 26 "Liquid Glass" scroll-edge effect)
// only exist in the SDK that ships with Xcode, not the plain Command Line
// Tools SDK this project otherwise builds against — the same split that
// already applies to FoundationModels, gated with `#if canImport`
// elsewhere. A SwiftUI *member* on an always-present framework can't be
// `canImport`-gated the same way, so this detects the active SDK's version
// at build-plan time and passes a compilation condition down instead.
func activeSDKVersion() -> (major: Int, minor: Int) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--sdk", "macosx", "--show-sdk-version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let parts = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".").compactMap { Int($0) }
        return (parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
    } catch {
        return (0, 0)
    }
}

// HAS_MACOS26_4_SDK: FoundationModels' `tokenCount(for:)` (macOS 26.4+),
// for exact on-device context budgeting.
let sdk = activeSDKVersion()
let swiftSettings: [SwiftSetting] = (sdk.major >= 26 ? [.define("HAS_MACOS26_SDK")] : [])
    + (sdk.major > 26 || (sdk.major == 26 && sdk.minor >= 4) ? [.define("HAS_MACOS26_4_SDK")] : [])

// Tachikoma (remote language models: OpenRouter, later OpenAI/Anthropic/…)
// needs Swift 6.2. The plain Command Line Tools toolchain may be older, so
// it is added only where it can build; sources gate on
// `#if canImport(Tachikoma)`.
#if compiler(>=6.2)
let remoteModelDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/openclaw/Tachikoma.git", from: "0.5.1")
]
let remoteModelProducts: [Target.Dependency] = [
    .product(name: "Tachikoma", package: "Tachikoma")
]
#else
let remoteModelDependencies: [Package.Dependency] = []
let remoteModelProducts: [Target.Dependency] = []
#endif

// The local SQLite mirror of EventKit (event source and search index).
let packageDependencies: [Package.Dependency] = remoteModelDependencies + [
    .package(path: "../CalendarIndex")
]
let shellDependencies: [Target.Dependency] = [
    .product(name: "CalendarIndex", package: "CalendarIndex"),
    .product(name: "CalendarIndexEventKit", package: "CalendarIndex")
]

let package = Package(
    name: "DayEdge",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    products: [
        // Everything the app is; started by the Xcode app target (DayEdge.app).
        .library(name: "Shell", targets: ["Shell"]),
    ],
    dependencies: packageDependencies,
    targets: [
        // Shared values and contracts: events, tasks, dates, decisions.
        // Foundation only (scripts/check-modules.sh).
        .target(
            name: "Domain",
            path: "Sources/Domain",
            resources: [.process("Localization")],
            swiftSettings: swiftSettings
        ),
        // EventKit, the calendar index, permissions, weather and holidays —
        // what implements Domain's contracts. Only the app imports it.
        .target(
            name: "Platform",
            dependencies: ["Domain",
                           .product(name: "CalendarIndex", package: "CalendarIndex"),
                           .product(name: "CalendarIndexEventKit", package: "CalendarIndex")],
            path: "Sources/Platform",
            resources: [.process("Localization")],
            swiftSettings: swiftSettings
        ),
        // What every feature draws with: theme, formatting environments,
        // shared controls, event/task rows and details, editors, decision
        // cards, and the shared event/task coordinators. Never Platform.
        .target(
            name: "UI",
            dependencies: ["Domain"],
            path: "Sources/UI",
            resources: [.process("Resources"), .process("Localization")],
            swiftSettings: swiftSettings
        ),
        // Month and Day: the month grid and its agenda, the day timeline,
        // their navigation, scrolling and stores.
        .target(
            name: "Agenda",
            dependencies: ["Domain", "UI"],
            path: "Sources/Agenda",
            resources: [.process("Localization")],
            swiftSettings: swiftSettings
        ),
        // The Tasks view: sections, navigator, sorting and its store.
        .target(
            name: "Tasks",
            dependencies: ["Domain", "UI"],
            path: "Sources/Tasks",
            resources: [.process("Localization")],
            swiftSettings: swiftSettings
        ),
        // Search (parsing, palette, results), Quick Add and Ask (backends,
        // tools, chat) with Intelligence settings. The only target with
        // the remote-model products (Tachikoma) and the date parser.
        .target(
            name: "Intelligence",
            dependencies: ["Domain", "UI"] + remoteModelProducts,
            path: "Sources/Intelligence",
            resources: [.process("Resources"), .process("Localization")],
            swiftSettings: swiftSettings
        ),
        // The app's shell: composition (the panel's object graph), the menu
        // bar, Meeting HUD, onboarding and Settings. The only target that
        // imports Platform.
        .target(
            name: "Shell",
            dependencies: ["Domain", "Platform", "UI", "Agenda", "Tasks", "Intelligence"] + shellDependencies,
            path: "Sources/Shell",
            resources: [.process("Resources"), .process("Localization")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DayEdgeTests",
            dependencies: ["Domain", "Platform", "UI", "Agenda", "Tasks", "Intelligence", "Shell"]
                + shellDependencies + remoteModelProducts,
            path: "Tests/DayEdgeTests",
            // Parser snapshots, read from the source tree (GoldenSnapshot).
            exclude: ["Golden"],
            resources: [.copy("Fixtures/Localization")],
            swiftSettings: swiftSettings
        )
    ]
)
