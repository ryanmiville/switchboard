import Foundation

// The app and the CLI both edit config.json, with no daemon between them. Every save is a compare-and-swap
// against the revision the edit started from, so neither silently overwrites the other's changes.
struct ConfigStore {
    var url = Config.configPath

    struct Snapshot {
        var config: Config
        // SHA-256 of the file's bytes. A missing file has the revision of no bytes.
        var revision: String
        var exists: Bool
    }

    static func revision(of data: Data) -> String { SHA256.hex(data) }

    func load() throws -> Snapshot {
        guard let data = try read() else {
            return Snapshot(config: .defaults, revision: Self.revision(of: Data()), exists: false)
        }
        do {
            return Snapshot(
                config: try JSONDecoder().decode(Config.self, from: data), revision: Self.revision(of: data),
                exists: true)
        } catch {
            throw ConfigStoreError.invalid(Self.describe(error), revision: Self.revision(of: data))
        }
    }

    func currentRevision() throws -> String {
        Self.revision(of: try read() ?? Data())
    }

    // Pass nil only when no earlier read exists to compare against.
    @discardableResult
    func save(_ config: Config, expecting revision: String?) throws -> String {
        let data = try config.encoded()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The lock closes the window between checking the revision and replacing the file.
        return try FileLock(url: url.appendingPathExtension("lock")).withLock {
            if let revision, try currentRevision() != revision { throw ConfigStoreError.conflict }
            try data.write(to: url, options: .atomic)
            return Self.revision(of: data)
        }
    }

    private func read() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw ConfigStoreError.unreadable(error.localizedDescription)
        }
    }

    static func describe(_ error: Error) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            codingPath.isEmpty
                ? "the top level"
                : codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch error as? DecodingError {
        case .keyNotFound(let key, let context):
            return "“\(key.stringValue)” is missing at \(path(context.codingPath))."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context.codingPath)) has the wrong type. \(context.debugDescription)"
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty
                ? "The file isn’t valid JSON."
                : "\(path(context.codingPath)) is invalid. \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }
}

enum ConfigStoreError: LocalizedError, Equatable {
    case unreadable(String)
    case invalid(String, revision: String)
    case conflict

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason): "The configuration file couldn’t be read. \(reason)"
        case .invalid(let reason, _): "The configuration file is invalid. \(reason)"
        case .conflict: "The configuration file changed since it was loaded."
        }
    }
}

// An advisory flock on a sibling file, shared by every process that writes the guarded file.
struct FileLock {
    let url: URL

    func withLock<T>(_ body: () throws -> T) throws -> T {
        let descriptor = open(url.path, O_RDWR | O_CREAT, 0o600)
        guard descriptor >= 0 else { throw FileSystemError(action: "open", url: url) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw FileSystemError(action: "lock", url: url) }
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}

struct FileSystemError: LocalizedError {
    let message: String

    // Call directly after the failing system call, while errno still describes it.
    init(action: String, url: URL) {
        message = "Couldn’t \(action) \(url.path): \(String(cString: strerror(errno)))."
    }

    var errorDescription: String? { message }
}
