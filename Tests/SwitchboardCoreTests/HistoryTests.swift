import Foundation
import SwitchboardFixtures
import Testing

@testable import SwitchboardCore

struct HistoryTests {
    func entry(_ n: Int) -> History.Entry {
        History.Entry(
            id: String(format: "%08x", n), time: Timestamp(Int64(n)).rfc3339, url: "https://example.com/\(n)",
            source: .default, browser: "b", profile: "Default", result: .launched)
    }

    func mode(_ path: String) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
            ?? -1
    }

    @Test func redactionHidesQueriesFragmentsAndPasswords() {
        #expect(History.redact("https://u:p@x.com/a?t=1#f") == "https://…@x.com/a?…#…")
        #expect(History.redact("https://x.com/a?#") == "https://x.com/a?#")
        #expect(History.redact("https://x.com/a@b") == "https://x.com/a@b")
    }

    @Test func entriesComeBackNewestFirstAndTrimToTheNewest200() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let store = fixture.historyStore
        for n in 0...History.trimAt { try store.append(entry(n)) }
        let entries = try store.entries()
        #expect(entries.count == History.keep)
        #expect(entries[0] == entry(History.trimAt))
        let lines = String(decoding: try Data(contentsOf: store.url), as: UTF8.self).split(separator: "\n")
        #expect(lines.count == History.keep)
        #expect(try mode(store.url.path) == 0o600)
        #expect(try mode(store.url.deletingLastPathComponent().path) == 0o700)
    }

    @Test func aLineThatDoesNotParseHidesNothingElse() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let store = fixture.historyStore
        try store.append(entry(1))
        let handle = try FileHandle(forWritingTo: store.url)
        handle.seekToEndOfFile()
        handle.write(Data("{oops\n".utf8))
        handle.closeFile()
        try store.append(entry(2))
        #expect(try store.entries() == [entry(2), entry(1)])
    }

    @Test func clearingRemovesTheFileAndTheLastError() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let store = fixture.historyStore
        try store.append(entry(1))
        store.recordWriteError(FileError(message: "disk full"), at: Timestamp(0))
        #expect(store.lastWriteError?.contains("disk full") == true)
        #expect(try store.clear() == 1)
        #expect(try store.entries().isEmpty)
        #expect(store.lastWriteError == nil)
    }

    @Test func recordingResolvesTheProfileAndSkipsWhenHistoryIsOff() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let helium = try fixture.installBrowser(.helium, name: "Helium", profiles: [("Profile 1", "Work")])
        var config = Config(
            browser: helium, defaultProfile: "Work", rules: [Rule(.domain, "x.com", profile: "Work")])
        let store = fixture.historyStore
        let error = History.record(
            "https://x.com/a?token=1", destination: config.destination(of: config.rules[0]), origin: .rule(0),
            config: config, error: nil, now: Timestamp(1_761_757_451), store: store,
            browsers: fixture.browsers)
        #expect(error == nil)
        let saved = try #require(try store.entries().first)
        #expect(saved.profile == "Profile 1")
        #expect(saved.profileName == "Work")
        #expect(saved.rule == History.RuleSnapshot(index: 1, condition: .domain, value: "x.com"))
        #expect(saved.time == "2025-10-29T17:04:11Z")
        #expect(saved.url == "https://x.com/a?token=1", "the file keeps the full link; output redacts it")

        config.history = HistorySettings(enabled: false)
        History.record(
            "https://y.com", destination: config.defaultDestination, origin: .default, config: config,
            error: nil,
            now: Timestamp(0), store: store, browsers: fixture.browsers)
        #expect(try store.entries().count == 1)
    }
}
