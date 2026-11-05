import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// A log of the links Switchboard opened, so an agent can find "that last link" without the person
// pasting it. Append-only JSON Lines, newest last, trimmed to the newest `History.keep` entries.
//
// Recording is best effort: `History.record` never fails a link. A failed write is kept in
// history.jsonl.error for `doctor` and cleared by the next success.

public enum History {
    public static let keep = 200
    public static let trimAt = 400

    public enum Source: String, Codable, Sendable { case rule, `default`, picker }
    public enum Outcome: String, Codable, Sendable { case launched, failed }

    /// The rule as it was when the link opened; positions change later.
    public struct RuleSnapshot: Codable, Equatable, Sendable {
        /// 1-based, as `rules list` shows it.
        public var index: Int
        public var condition: Condition
        public var value: String

        public init(index: Int, condition: Condition, value: String) {
            self.index = index
            self.condition = condition
            self.value = value
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var id: String
        /// RFC 3339, UTC.
        public var time: String
        public var url: String
        public var source: Source
        public var rule: RuleSnapshot?
        public var browser: String
        public var profile: String
        public var profileName: String?
        public var result: Outcome
        public var error: String?

        public init(
            id: String, time: String, url: String, source: Source, rule: RuleSnapshot? = nil, browser: String,
            profile: String, profileName: String? = nil, result: Outcome, error: String? = nil
        ) {
            self.id = id
            self.time = time
            self.url = url
            self.source = source
            self.rule = rule
            self.browser = browser
            self.profile = profile
            self.profileName = profileName
            self.result = result
            self.error = error
        }

        public var timestamp: Timestamp? { Timestamp(rfc3339: time) }
        public var redactedURL: String { History.redact(url) }
    }

    /// Eight random lowercase hex characters.
    public static func newID() -> String {
        String(format: "%08x", UInt32.random(in: .min ... .max))
    }

    /// Replaces the query, fragment and user info, which can carry tokens from magic links and
    /// OAuth callbacks: `https://u:p@x.com/a?t=1#f` → `https://…@x.com/a?…#…`.
    public static func redact(_ url: String) -> String {
        var base = Array(url.utf8)
        var suffix = ""
        if let hash = base.firstIndex(of: UInt8(ascii: "#")) {
            suffix = hash + 1 < base.count ? "#…" : "#"
            base = Array(base[..<hash])
        }
        if let question = base.firstIndex(of: UInt8(ascii: "?")) {
            suffix = (question + 1 < base.count ? "?…" : "?") + suffix
            base = Array(base[..<question])
        }
        if let scheme = Bytes.firstRange(of: Array("://".utf8), in: base) {
            let start = scheme.upperBound
            let end = base[start...].firstIndex(of: UInt8(ascii: "/")) ?? base.count
            if let at = base[start..<end].lastIndex(of: UInt8(ascii: "@")) {
                base.replaceSubrange(start..<at, with: Array("…".utf8))
            }
        }
        return String(decoding: base, as: UTF8.self) + suffix
    }

    /// Where a link's destination came from.
    public enum Origin: Equatable, Sendable {
        /// The rule at this 0-based index in the config used.
        case rule(Int)
        case `default`
        case picker
    }

    /// Records a link if history is enabled. Never fails the link: a write failure is returned for
    /// logging and kept for `doctor`.
    @discardableResult
    public static func record(
        _ url: String, destination: Destination, origin: Origin, config: Config, error: String?,
        now: Timestamp,
        store: HistoryStore, browsers: Browsers
    ) -> FileError? {
        guard config.historyEnabled else { return nil }
        let source: Source
        var rule: RuleSnapshot?
        switch origin {
        case .rule(let index):
            source = .rule
            if config.rules.indices.contains(index) {
                let r = config.rules[index]
                rule = RuleSnapshot(index: index + 1, condition: r.condition, value: r.value)
            }
        case .default: source = .default
        case .picker: source = .picker
        }
        var entry = Entry(
            id: newID(), time: now.rfc3339, url: url, source: source, rule: rule,
            browser: destination.browser,
            profile: destination.profile, result: error == nil ? .launched : .failed, error: error)
        if let list = try? Profiles.of(browsers, destination.browser),
            let directory = try? Profiles.directory(destination.profile, in: list)
        {
            entry.profileName = list.first { $0.directory == directory }?.name
            entry.profile = directory
        }
        do {
            try store.append(entry)
            return nil
        } catch {
            store.recordWriteError(error, at: now)
            return error
        }
    }
}

public struct HistoryStore: Sendable {
    public var url: URL

    public init(url: URL) { self.url = url }

    public var errorURL: URL { Files.withSuffix(url, ".error") }
    var lockURL: URL { Files.withSuffix(url, ".lock") }

    /// The newest `History.keep` entries, newest first. Lines that don't parse are skipped, so one
    /// bad line doesn't hide the rest.
    public func entries() throws(FileError) -> [History.Entry] {
        guard let data = try Files.contents(of: url) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).reversed().lazy
            .compactMap { try? decoder.decode(History.Entry.self, from: Data($0)) }
            .prefix(History.keep).map { $0 }
    }

    /// Appends one entry, creating the folder (0700) and file (0600) when needed.
    public func append(_ entry: History.Entry) throws(FileError) {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            if mkdir(directory.path, 0o700) != 0, errno != EEXIST { throw FileError("create", directory) }
        }
        var line = JSON.line(entry)
        line.append(UInt8(ascii: "\n"))
        let lock = try FileLock(url: lockURL)
        defer { lock.unlock() }
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard descriptor >= 0 else { throw FileError("open", url) }
        let written = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        let failure = written == line.count ? nil : FileError("write", url)
        close(descriptor)
        if let failure { throw failure }
        try trim()
        // Best effort: a stale error note only makes `doctor` report an old failure.
        unlink(errorURL.path)
    }

    /// Deletes the history and returns how many entries it had.
    @discardableResult
    public func clear() throws(FileError) -> Int {
        let count = (try? entries().count) ?? 0
        if FileManager.default.fileExists(atPath: url.path) {
            let lock = try FileLock(url: lockURL)
            defer { lock.unlock() }
            if unlink(url.path) != 0, errno != ENOENT { throw FileError("remove", url) }
        }
        if unlink(errorURL.path) != 0, errno != ENOENT { throw FileError("remove", errorURL) }
        return count
    }

    public var lastWriteError: String? {
        guard let data = try? Files.contents(of: errorURL) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public func recordWriteError(_ error: FileError, at time: Timestamp) {
        // Best effort: there is nowhere else to report a failure to record a failure.
        try? Files.replace(errorURL, with: Data("\(time.rfc3339) \(error.message)\n".utf8))
    }

    private func trim() throws(FileError) {
        guard let data = try Files.contents(of: url) else { return }
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
        guard lines.count > History.trimAt else { return }
        var kept = Data()
        for line in lines.suffix(History.keep) {
            kept.append(line)
            kept.append(UInt8(ascii: "\n"))
        }
        try Files.replace(url, with: kept, mode: 0o600)
    }
}

extension FileError {
    /// A failure that didn't come from a system call.
    public init(message: String) { self.message = message }
}

extension Bytes {
    static func firstRange(of needle: [UInt8], in haystack: [UInt8]) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return start..<(start + needle.count)
        }
        return nil
    }
}
