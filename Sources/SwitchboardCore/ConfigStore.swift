import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// Compare-and-swap saves of config.json. The app and the CLI both write it with no daemon between
// them, so every save checks that the file is still the one the edit started from.
//
// - The revision is the SHA-256 of the file's bytes; a missing file has the revision of no bytes.
// - A save takes an exclusive flock on config.json.lock, re-reads the revision, and refuses with
//   `.conflict` if it changed. Otherwise it replaces the file atomically.
// - A file that doesn't parse is reported, never replaced by defaults.

public enum StoreError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    /// The file exists but isn't a valid config. Carries its revision, so a later save can replace
    /// exactly that file once the person chooses to.
    case invalid(message: String, revision: String)
    case conflict
    case writeFailed(String)

    public var description: String {
        switch self {
        case .unreadable(let why): "The configuration file couldn’t be read. \(why)"
        case .invalid(let message, _): "The configuration file is invalid: \(message)"
        case .conflict: "The configuration file changed since it was loaded."
        case .writeFailed(let why): "The configuration file couldn’t be saved. \(why)"
        }
    }
}

public struct ConfigStore: Sendable {
    public struct Snapshot: Sendable {
        public var config: Config
        public var revision: String
        public var exists: Bool
    }

    public var url: URL

    public init(url: URL) { self.url = url }

    public static func revision(of data: Data) -> String { SHA256.hex(data) }

    public func load() throws(StoreError) -> Snapshot {
        guard let data = try read() else {
            return Snapshot(config: .defaults, revision: Self.revision(of: Data()), exists: false)
        }
        do {
            return Snapshot(config: try Config.parse(data), revision: Self.revision(of: data), exists: true)
        } catch {
            throw .invalid(message: JSON.describe(error, in: data), revision: Self.revision(of: data))
        }
    }

    public func currentRevision() throws(StoreError) -> String {
        Self.revision(of: try read() ?? Data())
    }

    /// Saves `config` if the file still has `expected` as its revision, and returns the new
    /// revision. Pass `nil` only when nothing was read first.
    @discardableResult
    public func save(_ config: Config, expecting expected: String?) throws(StoreError) -> String {
        let data = config.encoded()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .writeFailed("\(url.path): \(error.localizedDescription)")
        }
        let lock: FileLock
        do { lock = try FileLock(url: Files.withSuffix(url, ".lock")) } catch {
            throw .writeFailed(error.message)
        }
        defer { lock.unlock() }
        if let expected, try currentRevision() != expected { throw .conflict }
        do { try Files.replace(url, with: data) } catch { throw .writeFailed(error.message) }
        return Self.revision(of: data)
    }

    private func read() throws(StoreError) -> Data? {
        do {
            return try Files.contents(of: url)
        } catch {
            throw .unreadable(error.message)
        }
    }
}

/// A failed system call, described while `errno` still holds its reason.
public struct FileError: Error, Sendable {
    public let message: String

    init(_ action: String, _ url: URL) {
        message = "Couldn’t \(action) \(url.path): \(String(cString: strerror(errno)))."
    }
}

/// An exclusive advisory `flock` on a file, held until `unlock()`.
public final class FileLock {
    private let descriptor: Int32

    public init(url: URL) throws(FileError) {
        descriptor = open(url.path, O_RDWR | O_CREAT, 0o600)
        guard descriptor >= 0 else { throw FileError("open", url) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                let error = FileError("lock", url)
                close(descriptor)
                throw error
            }
        }
    }

    public func unlock() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

public enum Files {
    /// The file's bytes, or `nil` when it doesn't exist.
    public static func contents(of url: URL) throws(FileError) -> Data? {
        let descriptor = open(url.path, O_RDONLY)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw FileError("open", url)
        }
        defer { close(descriptor) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                throw FileError("read", url)
            }
            data.append(contentsOf: buffer[0..<count])
        }
    }

    /// `url` with `suffix` appended to its file name (`config.json` → `config.json.lock`).
    public static func withSuffix(_ url: URL, _ suffix: String) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + suffix)
    }

    /// Replaces `url` with `data` through a temporary file in the same folder, `fsync` and `rename`,
    /// so readers see either the old file or the new one. A new file gets `mode`.
    public static func replace(_ url: URL, with data: Data, mode: mode_t = 0o644) throws(FileError) {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UInt32.random(in: .min ... .max)).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard descriptor >= 0 else { throw FileError("create", temporary) }
        var failure: FileError?
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = FileError("write", temporary)
                    return
                }
                offset += written
            }
        }
        if failure == nil, fsync(descriptor) != 0 { failure = FileError("sync", temporary) }
        close(descriptor)
        if failure == nil, rename(temporary.path, url.path) != 0 { failure = FileError("replace", url) }
        if let failure {
            unlink(temporary.path)
            throw failure
        }
    }
}
