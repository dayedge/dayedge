import XCTest
@testable import Shell

final class AcknowledgementsTests: XCTestCase {
    /// Every package the app resolves — except Apple's own — is
    /// acknowledged, so a new dependency can't slip in unthanked.
    func testEveryNonApplePackageIsAcknowledged() throws {
        let resolved = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Package.resolved")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: resolved)) as? [String: Any]
        let pins = try XCTUnwrap(json?["pins"] as? [[String: Any]])
        func normalized(_ url: String) -> String {
            url.lowercased().replacingOccurrences(of: ".git", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let acknowledged = Set(Acknowledgement.all.map { normalized($0.homepage.absoluteString) })
        for pin in pins {
            let location = try XCTUnwrap(pin["location"] as? String)
            guard !location.lowercased().contains("github.com/apple/") else { continue }
            XCTAssertTrue(acknowledged.contains(normalized(location)), "\(location) needs an acknowledgement")
        }
    }

    func testEveryEntryNamesItsLicence() {
        for item in Acknowledgement.all {
            XCTAssertFalse(item.license.isEmpty, item.name)
            XCTAssertFalse(item.copyright.isEmpty, item.name)
        }
    }

    func testBundledNoticesCoverEveryResolvedPackage() throws {
        let resolved = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Package.resolved")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: resolved)) as? [String: Any]
        let pins = try XCTUnwrap(json?["pins"] as? [[String: Any]])
        for pin in pins {
            let identity = try XCTUnwrap(pin["identity"] as? String)
            let state = try XCTUnwrap(pin["state"] as? [String: String])
            let revision = try XCTUnwrap(state["revision"])
            XCTAssertTrue(LicenseView.thirdPartyText.contains("PACKAGE: \(identity)\n"), identity)
            XCTAssertTrue(LicenseView.thirdPartyText.contains("REVISION: \(revision)\n"), identity)
        }
    }

    func testBundledParserNoticesRetainPermissionText() {
        let notices = LicenseView.thirdPartyText
        XCTAssertTrue(notices.contains("COMPONENT: chrono-node\n"))
        XCTAssertTrue(notices.contains("Copyright (c) 2014, Wanasit Tanakitrungruang"))
        XCTAssertTrue(notices.contains("COMPONENT: dayjs\n"))
        XCTAssertTrue(notices.contains("Copyright (c) 2018-present, iamkun"))
        XCTAssertTrue(notices.contains("Permission is hereby granted, free of charge"))
    }

    /// About shows the bundled copy of the licence: it must be the
    /// repository's LICENSE, word for word.
    func testTheBundledLicenseIsTheRepositorysLicense() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let repository = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)
        XCTAssertEqual(LicenseView.text, repository.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertTrue(LicenseView.text.hasPrefix("Mozilla Public License Version 2.0"))
    }
}
