// swift-tools-version: 5.9
import PackageDescription

// CalendarIndex: a rebuildable SQLite mirror of EventKit — the app's
// future event source and full-text search. EventKit stays authoritative
// and the only write path; this package only reads it.
//
// `CalendarIndex` itself never imports EventKit (snapshots in, snapshots
// out, testable with a fake source); `CalendarIndexEventKit` is the one
// production adapter.
let package = Package(
    name: "CalendarIndex",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "CalendarIndex", targets: ["CalendarIndex"]),
        .library(name: "CalendarIndexEventKit", targets: ["CalendarIndexEventKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "CalendarIndex",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "CalendarIndexEventKit",
            dependencies: ["CalendarIndex"]
        ),
        .testTarget(
            name: "CalendarIndexTests",
            dependencies: ["CalendarIndex", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "CalendarIndexEventKitTests",
            dependencies: ["CalendarIndex", "CalendarIndexEventKit"]
        )
    ]
)
