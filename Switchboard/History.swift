import Foundation

// One link Switchboard opened (or tried to), from a rule, the default destination, or the picker.
struct HistoryEntry: Codable, Equatable {
    enum Source: String, Codable { case rule, `default`, picker }
    enum Outcome: String, Codable { case launched, failed }

    // Rule positions change later, so the entry keeps what the rule was at the time.
    struct RuleSnapshot: Codable, Equatable {
        var index: Int  // 1-based, as `switchboard rules list` shows it
        var condition: Condition
        var value: String
    }

    var id: String
    var time: Date
    var url: String
    var source: Source
    var rule: RuleSnapshot?
    var browser: String
    var profile: String
    var profileName: String?
    var result: Outcome
    var error: String?

    static func makeID() -> String {
        let digits = String(UInt32.random(in: .min ... .max), radix: 16)
        return String(repeating: "0", count: 8 - digits.count) + digits
    }

    var redactedURL: String { Self.redact(url) }

    // Query strings, fragments and passwords can carry tokens from magic links and OAuth callbacks.
    static func redact(_ url: String) -> String {
        var base = Substring(url)
        var suffix = ""
        if let hash = base.firstIndex(of: "#") {
            suffix = base.index(after: hash) < base.endIndex ? "#…" : "#"
            base = base[..<hash]
        }
        if let question = base.firstIndex(of: "?") {
            suffix = (base.index(after: question) < base.endIndex ? "?…" : "?") + suffix
            base = base[..<question]
        }
        var result = String(base)
        if let scheme = result.range(of: "://") {
            let authority =
                scheme.upperBound..<(result[scheme.upperBound...].firstIndex(of: "/") ?? result.endIndex)
            if let at = result[authority].lastIndex(of: "@") {
                result.replaceSubrange(authority.lowerBound..<at, with: "…")
            }
        }
        return result + suffix
    }
}

// Append-only JSON Lines, newest last, trimmed to the newest entries under the same lock pattern as the config.
struct HistoryStore {
    static let keep = 200
    static let trimThreshold = 400
    static let defaultURL = url(home: FileManager.default.homeDirectoryForCurrentUser)

    static func url(home: URL) -> URL {
        home.appendingPathComponent(".local/state/switchboard/history.jsonl")
    }

    var url = defaultURL

    // Written when an append fails so `switchboard doctor` can report it; removed by the next success.
    var errorURL: URL { url.appendingPathExtension("error") }
    private var lock: FileLock { FileLock(url: url.appendingPathExtension("lock")) }

    // Newest first. Lines that don't decode are skipped rather than hiding every other entry.
    func entries() throws -> [HistoryEntry] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let decoder = Self.decoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(HistoryEntry.self, from: $0) }
            .reversed()
    }

    func append(_ entry: HistoryEntry) throws {
        try createDirectory()
        var line = try Self.encoder().encode(entry)
        line.append(0x0A)
        try lock.withLock {
            let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
            guard descriptor >= 0 else { throw FileSystemError(action: "open", url: url) }
            defer { close(descriptor) }
            let written = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            guard written == line.count else { throw FileSystemError(action: "write to", url: url) }
            try trimIfNeeded()
        }
        if FileManager.default.fileExists(atPath: errorURL.path) {
            try? FileManager.default.removeItem(at: errorURL)
        }
    }

    // Returns the number of entries removed.
    @discardableResult
    func clear() throws -> Int {
        var count = 0
        if FileManager.default.fileExists(atPath: url.path) {
            count = (try? entries().count) ?? 0
            try lock.withLock { try FileManager.default.removeItem(at: url) }
        }
        if FileManager.default.fileExists(atPath: errorURL.path) {
            try FileManager.default.removeItem(at: errorURL)
        }
        return count
    }

    func lastWriteError() -> String? {
        guard let text = try? String(contentsOf: errorURL, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func recordWriteError(_ error: Error, at date: Date) {
        let message = "\(ISO8601DateFormatter().string(from: date)) \(error.localizedDescription)\n"
        try? Data(message.utf8).write(to: errorURL, options: .atomic)
    }

    private func createDirectory() throws {
        let directory = url.deletingLastPathComponent()
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(
            at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            // Another process may have created it first.
            guard FileManager.default.fileExists(atPath: directory.path) else { throw error }
        }
    }

    private func trimIfNeeded() throws {
        let lines = try Data(contentsOf: url).split(separator: 0x0A)
        guard lines.count > Self.trimThreshold else { return }
        var kept = Data(lines.suffix(Self.keep).joined(separator: [0x0A]))
        kept.append(0x0A)
        try kept.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// Recording is best effort: it never throws, so a history failure can't turn a working link into a
// failure. Callers log the returned error.
struct HistoryRecorder {
    enum Origin {
        case rule(Route)
        case `default`
        case picker
    }

    var store = HistoryStore()
    var profileStore = BrowserProfiles()
    var now: () -> Date = { Date() }

    static func origin(of decision: (destination: Destination, route: Route?)) -> Origin {
        decision.route.map(Origin.rule) ?? .default
    }

    @discardableResult
    func record(url: URL, destination: Destination, origin: Origin, config: Config, error: Error?) -> Error? {
        guard config.historyEnabled else { return nil }
        var entry = HistoryEntry(
            id: HistoryEntry.makeID(), time: now(), url: url.absoluteString, source: .default,
            browser: destination.browser, profile: destination.profile,
            result: error == nil ? .launched : .failed, error: error?.localizedDescription)
        switch origin {
        case .rule(let route):
            entry.source = .rule
            if let index = config.routes.firstIndex(where: { $0.id == route.id }) {
                entry.rule = HistoryEntry.RuleSnapshot(
                    index: index + 1, condition: route.condition, value: route.value)
            }
        case .default:
            entry.source = .default
        case .picker:
            entry.source = .picker
        }
        if let profiles = try? profileStore.profiles(browserPath: destination.browser),
            let directory = try? BrowserProfiles.directory(for: destination.profile, in: profiles)
        {
            entry.profile = directory
            entry.profileName = profiles.first { $0.directory == directory }?.name
        }
        do {
            try store.append(entry)
            return nil
        } catch {
            store.recordWriteError(error, at: entry.time)
            return error
        }
    }
}
