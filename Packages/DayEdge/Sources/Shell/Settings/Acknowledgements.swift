import Foundation

/// The open-source software, fonts and open data the app is built with,
/// shown in About → Acknowledgements. Apple's own Swift packages aren't
/// listed. Keep in step with `Package.resolved` and the bundled resources
/// (`chrono.js`, `BricolageGrotesque.ttf`).
struct Acknowledgement: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case software = "Software"
        case font = "Fonts"
        case data = "Data"

        var title: String {
            switch self {
            case .software: return L10n.tr("acknowledgements.software", "Software")
            case .font: return L10n.tr("acknowledgements.fonts", "Fonts")
            case .data: return L10n.tr("acknowledgements.data", "Data")
            }
        }
    }

    var id: String { name }
    let name: String
    let kind: Kind
    let license: String
    /// What it does here, in a few words.
    let role: String
    let copyright: String
    let homepage: URL

    static let all: [Acknowledgement] = [
        .init(name: "Chrono", kind: .software, license: "MIT",
              role: L10n.tr("acknowledgements.role.chrono", "Understands dates and times written in plain language."),
              copyright: "Copyright © 2014 Wanasit Tanakitrungruang",
              homepage: URL(string: "https://github.com/wanasit/chrono")!),
        .init(name: "Day.js", kind: .software, license: "MIT",
              role: L10n.tr("acknowledgements.role.dayjs", "Date arithmetic inside Chrono."),
              copyright: "Copyright © 2018 iamkun",
              homepage: URL(string: "https://github.com/iamkun/dayjs")!),
        .init(name: "GRDB", kind: .software, license: "MIT",
              role: L10n.tr("acknowledgements.role.grdb", "The SQLite toolkit behind the local calendar index and search."),
              copyright: "Copyright © 2015–2025 Gwendal Roué",
              homepage: URL(string: "https://github.com/groue/GRDB.swift")!),
        .init(name: "Tachikoma", kind: .software, license: "MIT",
              role: L10n.tr("acknowledgements.role.tachikoma", "Connects Ask to the language-model providers you choose."),
              copyright: "Copyright © 2026 Peter Steinberger",
              homepage: URL(string: "https://github.com/openclaw/Tachikoma")!),
        .init(name: "MCP Swift SDK", kind: .software, license: "Apache 2.0 / MIT",
              role: L10n.tr("acknowledgements.role.mcp", "Model Context Protocol support, used by Tachikoma."),
              copyright: "The Model Context Protocol contributors",
              homepage: URL(string: "https://github.com/modelcontextprotocol/swift-sdk")!),
        .init(name: "EventSource", kind: .software, license: "MIT",
              role: L10n.tr("acknowledgements.role.eventsource", "Streams model replies as they're written, used by Tachikoma."),
              copyright: "Copyright © 2025 Mattt",
              homepage: URL(string: "https://github.com/mattt/eventsource")!),
        .init(name: "Swift Service Lifecycle", kind: .software, license: "Apache 2.0",
              role: L10n.tr("acknowledgements.role.lifecycle", "Service start-up and shutdown, used by Tachikoma."),
              copyright: "Copyright © 2019–2023 The ServiceLifecycle Project",
              homepage: URL(string: "https://github.com/swift-server/swift-service-lifecycle")!),
        .init(name: "Bricolage Grotesque", kind: .font, license: "SIL OFL 1.1",
              role: L10n.tr("acknowledgements.role.bricolage", "The Day/Edge wordmark."),
              copyright: "Copyright © 2022 The Bricolage Grotesque Project Authors",
              homepage: URL(string: "https://github.com/ateliertriay/bricolage")!),
        .init(name: "Open-Meteo", kind: .data, license: "CC BY 4.0",
              role: L10n.tr("acknowledgements.role.meteo", "Weather forecasts in the agenda and the Day view."),
              copyright: "Weather data by Open-Meteo.com",
              homepage: URL(string: "https://open-meteo.com")!),
        // ODbL 1.0 (the data repository's LICENSE): holidays shown in the
        // app are a Produced Work, which needs this notice.
        .init(name: "OpenHolidays", kind: .data, license: "ODbL 1.0",
              role: L10n.tr("acknowledgements.role.holidays", "Public and school holidays on the calendar."),
              copyright: "Contains information from OpenHolidays, which is made available under the Open Database License (ODbL).",
              homepage: URL(string: "https://www.openholidaysapi.org")!)
    ]
}

/// Public project and optional support links.
enum AppLinks {
    static let github = URL(string: "https://github.com/dayedge/dayedge")!
    static let website = URL(string: "https://dayedge.app")!
    static let kofi = URL(string: "https://ko-fi.com/dayedge")!
}
