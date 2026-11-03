import Foundation
import SwitchboardFixtures
import Testing

@testable import SwitchboardCore

struct StoreTests {
    @Test func aMissingFileLoadsDefaultsWithTheEmptyRevision() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let snapshot = try fixture.configStore.load()
        #expect(!snapshot.exists)
        #expect(snapshot.config == .defaults)
        #expect(snapshot.revision == ConfigStore.revision(of: Data()))
        #expect(snapshot.revision == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func aSaveFromAStaleRevisionIsRefusedAndLeavesTheFileAlone() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let store = fixture.configStore
        let start = try store.load()
        var theirs = start.config
        theirs.rules.append(Rule(.domain, "a.com", profile: "Default"))
        try store.save(theirs, expecting: start.revision)
        let onDisk = try Data(contentsOf: store.url)

        var mine = start.config
        mine.defaultProfile = "Profile 1"
        #expect(throws: StoreError.conflict) { try store.save(mine, expecting: start.revision) }
        #expect(try Data(contentsOf: store.url) == onDisk)
    }

    @Test func aSaveReturnsTheRevisionOfWhatItWrote() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let store = fixture.configStore
        let config = Config(browser: "b")
        let revision = try store.save(config, expecting: ConfigStore.revision(of: Data()))
        #expect(revision == (try store.currentRevision()))
        #expect(try store.load().config == config)
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: store.url.deletingLastPathComponent().path)
        #expect(
            leftovers.sorted() == ["config.json", "config.json.lock"], "no temporary files are left behind")
    }

    @Test func aMalformedFileIsReportedWithItsPositionAndNeverReplaced() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let store = fixture.configStore
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = Data(#"{"browser": "#.utf8)
        try broken.write(to: store.url)
        #expect {
            try store.load()
        } throws: { error in
            guard case .invalid(let message, let revision) = error as? StoreError else { return false }
            return message.contains("line 1") && revision == ConfigStore.revision(of: broken)
        }
        #expect(try Data(contentsOf: store.url) == broken)
    }
}

struct JSONSyntaxTests {
    @Test func theFirstErrorIsFoundWithItsLineAndColumn() {
        func failure(_ text: String) -> String? { JSONSyntax.firstError(in: Array(text.utf8))?.description }
        #expect(failure(#"{"a": [1, 2], "b": {"c": "d"}}"#) == nil)
        #expect(
            failure(#"{"browser": "#) == "The document ends where a value was expected at line 1, column 13.")
        #expect(failure("{\n  \"a\": 1\n  \"b\": 2\n}") == "Expected “,” or “}” at line 3, column 3.")
        #expect(failure("[1,]") == "Unexpected character where a value was expected at line 1, column 4.")
        #expect(
            failure("{\"é\": x}") == "Unexpected character where a value was expected at line 1, column 7.")
    }
}
