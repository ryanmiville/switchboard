import Foundation
import Testing

@testable import SwitchboardCore

struct HistoryTests {
    private func entry(_ url: String, id: String = HistoryEntry.makeID(), time: Date = Date()) -> HistoryEntry
    {
        HistoryEntry(
            id: id, time: time, url: url, source: .default, browser: "/Applications/Helium.app",
            profile: "Default",
            result: .launched)
    }

    private func permissions(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    @Test func entriesAreAppendedPrivatelyAndReadNewestFirst() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = HistoryStore(url: fixture.historyURL)
        #expect(try store.entries().isEmpty)
        let first = entry("https://example.com/1", time: Date(timeIntervalSince1970: 1_800_000_000))
        try store.append(first)
        try store.append(entry("https://example.com/2"))
        #expect(try store.entries().map(\.url) == ["https://example.com/2", "https://example.com/1"])
        #expect(try store.entries().last == first)
        #expect(try permissions(fixture.historyURL) & 0o777 == 0o600)
        #expect(try permissions(fixture.historyURL.deletingLastPathComponent()) & 0o777 == 0o700)
        let line = try #require(
            String(decoding: Data(contentsOf: fixture.historyURL), as: UTF8.self).split(separator: "\n").first
        )
        #expect(line.contains(#""time":"2027-01-15T08:00:00Z""#))
        #expect(line.contains(#""url":"https://example.com/1""#))
    }

    @Test func theFileIsTrimmedToTheNewestEntries() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = HistoryStore(url: fixture.historyURL)
        for index in 0...HistoryStore.trimThreshold {
            try store.append(entry("https://example.com/\(index)"))
        }
        let entries = try store.entries()
        #expect(entries.count == HistoryStore.keep)
        #expect(entries.first?.url == "https://example.com/\(HistoryStore.trimThreshold)")
        #expect(try permissions(fixture.historyURL) & 0o777 == 0o600)
        try store.append(entry("https://example.com/next"))
        #expect(try store.entries().count == HistoryStore.keep)
        #expect(try store.entries().first?.url == "https://example.com/next")
        let lines = try Data(contentsOf: fixture.historyURL).split(separator: 0x0A)
        #expect(lines.count == HistoryStore.keep + 1)
    }

    @Test(arguments: [
        ("https://github.com/acme/api/pull/12", "https://github.com/acme/api/pull/12"),
        ("https://accounts.example.com/callback?code=secret", "https://accounts.example.com/callback?…"),
        ("https://example.com/a#access_token=secret", "https://example.com/a#…"),
        ("https://example.com/a?x=1#y", "https://example.com/a?…#…"),
        ("https://user:secret@example.com/a", "https://…@example.com/a"),
        ("https://example.com/a?", "https://example.com/a?"),
        ("https://example.com/@me", "https://example.com/@me"),
    ])
    func urlsAreRedacted(url: String, redacted: String) {
        #expect(HistoryEntry.redact(url) == redacted)
    }

    @Test func malformedLinesDoNotHideOtherEntries() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = HistoryStore(url: fixture.historyURL)
        try store.append(entry("https://example.com/1"))
        let handle = try FileHandle(forWritingTo: fixture.historyURL)
        handle.seekToEndOfFile()
        handle.write(Data("{ not json\n".utf8))
        handle.closeFile()
        try store.append(entry("https://example.com/2"))
        #expect(try store.entries().map(\.url) == ["https://example.com/2", "https://example.com/1"])
    }

    @Test func clearingDeletesTheFile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = HistoryStore(url: fixture.historyURL)
        #expect(try store.clear() == 0)
        try store.append(entry("https://example.com/1"))
        try store.append(entry("https://example.com/2"))
        #expect(try store.clear() == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.historyURL.path))
        #expect(try store.entries().isEmpty)
    }

    @Test func recordingDescribesTheRuleAndProfileAndRespectsTheSetting() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        try fixture.profiles(["Default": "Ryan", "Profile 1": "H3"], folder: "net.imput.helium")
        var config = Config(
            browser: helium.path, defaultProfile: "Ryan",
            routes: [
                Route(condition: .domain, value: "youtube.com", profile: "Profile 1"),
                Route(condition: .domain, value: "github.com", profile: "H3"),
            ])
        let recorder = HistoryRecorder(
            store: HistoryStore(url: fixture.historyURL),
            profileStore: BrowserProfiles(homeDirectory: fixture.root))
        let link = try #require(URL(string: "https://github.com/acme?token=1"))
        let decision = Router(config: config).decision(url: link)
        #expect(
            recorder.record(
                url: link, destination: decision.destination, origin: HistoryRecorder.origin(of: decision),
                config: config, error: nil) == nil)
        struct Failure: LocalizedError { var errorDescription: String? { "The browser didn’t start." } }
        let fallback = try #require(URL(string: "https://example.com"))
        let unmatched = Router(config: config).decision(url: fallback)
        recorder.record(
            url: fallback, destination: unmatched.destination, origin: HistoryRecorder.origin(of: unmatched),
            config: config, error: Failure())
        recorder.record(
            url: fallback, destination: Destination(browser: helium.path, profile: "Default"),
            origin: .picker,
            config: config, error: nil)
        let entries = try HistoryStore(url: fixture.historyURL).entries()
        #expect(entries.map(\.source) == [.picker, .default, .rule])
        let routed = try #require(entries.last)
        #expect(routed.url == "https://github.com/acme?token=1")
        #expect(routed.rule == HistoryEntry.RuleSnapshot(index: 2, condition: .domain, value: "github.com"))
        #expect(routed.profile == "Profile 1")
        #expect(routed.profileName == "H3")
        #expect(routed.result == .launched)
        #expect(entries[1].rule == nil)
        #expect(entries[1].profile == "Default")
        #expect(entries[1].result == .failed)
        #expect(entries[1].error == "The browser didn’t start.")

        config.history = HistorySettings(enabled: false)
        recorder.record(
            url: link, destination: decision.destination, origin: .default, config: config, error: nil)
        #expect(try HistoryStore(url: fixture.historyURL).entries().count == 3)
    }

    @Test func writeFailuresAreReturnedAndRememberedUntilTheNextSuccess() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = HistoryStore(url: fixture.historyURL)
        // A directory where the file should be makes every append fail, even when running as root.
        try FileManager.default.createDirectory(at: fixture.historyURL, withIntermediateDirectories: true)
        let recorder = HistoryRecorder(
            store: store, profileStore: BrowserProfiles(homeDirectory: fixture.root))
        let link = try #require(URL(string: "https://example.com"))
        let error = recorder.record(
            url: link, destination: Destination(browser: "/Missing.app", profile: "Default"),
            origin: .default,
            config: .defaults, error: nil)
        #expect(error != nil)
        #expect(store.lastWriteError() != nil)
        try FileManager.default.removeItem(at: fixture.historyURL)
        #expect(
            recorder.record(
                url: link, destination: Destination(browser: "/Missing.app", profile: "Default"),
                origin: .default,
                config: .defaults, error: nil) == nil)
        #expect(store.lastWriteError() == nil)
        #expect(try store.entries().count == 1)
    }
}
