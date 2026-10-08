import XCTest
@testable import Shell
@testable import Intelligence

final class AssistantSettingsTests: XCTestCase {
    func testTheDefaultIsLocalOnly() {
        let settings = AssistantSettings()
        XCTAssertNil(settings.activeProvider)
        XCTAssertFalse(settings.isUsingProvider)
        XCTAssertNil(settings.readyProvider)
        XCTAssertEqual(settings.configuration(for: .openRouter).modelID, "openai/gpt-5.6-luna", "a new provider starts on its suggested model")
    }

    func testAProviderIsReadyOnlyWithAKeyAndAModel() {
        var settings = AssistantSettings(activeProvider: .openRouter)
        XCTAssertNil(settings.readyProvider, "chosen, but no key yet")
        settings.providers[.openRouter] = ProviderConfiguration(apiKey: "sk-or-test", modelID: "  ")
        XCTAssertNil(settings.readyProvider, "no model")
        settings.providers[.openRouter]?.modelID = "openai/gpt-5.6-luna"
        XCTAssertEqual(settings.readyProvider?.kind, .openRouter)
    }

    func testTurningTheProviderOffKeepsItsKeyAndModel() throws {
        var settings = AssistantSettings(activeProvider: .openRouter,
                                         providers: [.openRouter: ProviderConfiguration(apiKey: "sk-or-test", modelID: "x/y")])
        settings.activeProvider = nil
        XCTAssertEqual(settings.configuration(for: .openRouter), ProviderConfiguration(apiKey: "sk-or-test", modelID: "x/y"))

        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AssistantSettings.self, from: data), settings)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"openRouter\":{"), "providers are keyed by name in the file")
    }
}

@MainActor
final class AssistantSettingsStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var file: URL { directory.appendingPathComponent("DayEdge/intelligence.json") }

    func testSavesAndReloadsInAPrivateFile() throws {
        let store = AssistantSettingsStore(fileURL: file)
        XCTAssertEqual(store.settings, .localOnly, "no file yet")
        store.update {
            $0.activeProvider = .openRouter
            $0.providers[.openRouter] = ProviderConfiguration(apiKey: "sk-or-test", modelID: "openai/gpt-5.6-luna")
        }

        XCTAssertEqual(AssistantSettingsStore(fileURL: file).settings, store.settings)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600, "only the user can read the key")
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true,
                       "no backup copy of the key")
        store.update { $0.providers[.openRouter]?.apiKey = "sk-or-other" }
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true,
                       "kept after an atomic rewrite")
    }

    func testAnUnreadableFileMeansLocalOnly() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        XCTAssertEqual(AssistantSettingsStore(fileURL: file).settings, .localOnly)
    }
}
