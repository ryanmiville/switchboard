import Foundation
import Testing

@testable import SwitchboardCore

struct ConfigStoreTests {
    @Test(arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (
            "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        ),
        (
            String(repeating: "a", count: 1000),
            "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"
        ),
    ])
    func revisionsAreSHA256(input: String, digest: String) {
        #expect(SHA256.hex(Data(input.utf8)) == digest)
    }

    @Test func externalChangesAreNeverOverwritten() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = ConfigStore(url: fixture.configURL)
        let config = Config(browser: "/Applications/Helium.app", defaultProfile: "Default", routes: [])
        let revision = try store.save(config, expecting: store.load().revision)
        #expect(try store.load().revision == revision)
        let external = Data(
            #"{"browser":"/Applications/Helium.app","defaultProfile":"Profile 1","routes":[]}"#.utf8)
        try external.write(to: fixture.configURL)
        var edited = config
        edited.routes.append(Route(condition: .domain, value: "github.com"))
        #expect(throws: ConfigStoreError.conflict) { try store.save(edited, expecting: revision) }
        #expect(try Data(contentsOf: fixture.configURL) == external)
        let current = try store.load()
        #expect(current.config.defaultProfile == "Profile 1")
        #expect(try store.save(edited, expecting: current.revision) == store.currentRevision())
    }

    @Test func savesKeepUnrelatedRulesAndTheAppsFormatting() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let legacy = Config(
            browser: "/Applications/Helium.app", defaultProfile: "Ryan",
            routes: [
                Route(
                    condition: .domain, value: "gitlab.com", profile: "Work",
                    browser: "/Applications/Google Chrome.app"),
                Route(condition: .contains, value: "youtube", profile: "H3"),
            ])
        try legacy.save(to: fixture.configURL)
        let original = try Data(contentsOf: fixture.configURL)
        let store = ConfigStore(url: fixture.configURL)
        let snapshot = try store.load()
        try store.save(snapshot.config, expecting: snapshot.revision)
        #expect(try Data(contentsOf: fixture.configURL) == original)
        var edited = try store.load().config
        edited.routes.append(Route(condition: .domain, value: "github.com", profile: "Profile 2"))
        try store.save(edited, expecting: ConfigStore.revision(of: original))
        let saved = try Config.load(from: fixture.configURL)
        #expect(saved.defaultProfile == "Ryan")
        #expect(saved.routes.map(\.profile) == ["Work", "H3", "Profile 2"])
        #expect(try Data(contentsOf: fixture.configURL) == edited.encoded())
    }

    @Test func malformedFilesAreReportedAndNeverReplaced() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = Data("{ broken JSON".utf8)
        try original.write(to: fixture.configURL)
        let store = ConfigStore(url: fixture.configURL)
        #expect(throws: ConfigStoreError.self) { try store.load() }
        do {
            _ = try store.load()
        } catch ConfigStoreError.invalid(_, let revision) {
            #expect(revision == ConfigStore.revision(of: original))
        }
        #expect(throws: ConfigStoreError.conflict) {
            try store.save(.defaults, expecting: ConfigStore.revision(of: Data()))
        }
        #expect(try Data(contentsOf: fixture.configURL) == original)
    }

    @Test func aMissingFileLoadsDefaultsAndIsCreatedByTheFirstSave() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = fixture.root.appendingPathComponent("nested/config.json")
        let store = ConfigStore(url: url)
        let snapshot = try store.load()
        #expect(!snapshot.exists)
        #expect(snapshot.config == .defaults)
        #expect(snapshot.revision == SHA256.hex(Data()))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try store.save(snapshot.config, expecting: snapshot.revision)
        #expect(try store.load().exists)
    }

    @Test func historySettingIsOptional() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let base = #""browser":"/Applications/Helium.app","defaultProfile":"Default","routes":[]"#
        try Data("{\(base)}".utf8).write(to: fixture.configURL)
        let omitted = try Config.load(from: fixture.configURL)
        #expect(omitted.historyEnabled)
        #expect(!String(decoding: try omitted.encoded(), as: UTF8.self).contains("history"))
        try Data(#"{\#(base),"history":{}}"#.utf8).write(to: fixture.configURL)
        #expect(try Config.load(from: fixture.configURL).historyEnabled)
        try Data(#"{\#(base),"history":{"enabled":false}}"#.utf8).write(to: fixture.configURL)
        let disabled = try Config.load(from: fixture.configURL)
        #expect(!disabled.historyEnabled)
        try disabled.save(to: fixture.configURL)
        #expect(try Config.load(from: fixture.configURL).history == HistorySettings(enabled: false))
    }
}
