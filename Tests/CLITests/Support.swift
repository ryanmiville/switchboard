import Foundation
import SwitchboardCore
import SwitchboardFixtures
import Testing

// End-to-end tests of the switchboard-next binary. Each test gets a temporary home with fixture
// browsers: real app bundles whose program records its arguments instead of opening anything.
// $SWITCHBOARD_NEXT_APPLICATIONS keeps the machine's real browsers out of view, and the binary
// runs with only this home in its environment.

/// A JSON value read from the binary's output, or built to write a fixture file.
enum JSONValue: Equatable, Codable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral,
    ExpressibleByNilLiteral
{
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
    init(nilLiteral: ()) { self = .null }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// A missing key reads as null; use `has` to tell them apart.
    subscript(key: String) -> JSONValue {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSONValue {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    func has(_ key: String) -> Bool {
        if case .object(let o) = self { return o[key] != nil }
        return false
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var array: [JSONValue] {
        if case .array(let a) = self { return a }
        return []
    }

    static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

struct Run {
    var status: Int32
    var stdout: String
    var stderr: String

    func json() throws -> JSONValue {
        do {
            return try JSONValue.parse(Data(stdout.utf8))
        } catch {
            Issue.record("not JSON: \(stdout)\n\(stderr)")
            throw error
        }
    }

    /// Requires a zero exit status.
    func ok(sourceLocation: SourceLocation = #_sourceLocation) throws -> Run {
        try #require(status == 0, "stdout: \(stdout)\nstderr: \(stderr)", sourceLocation: sourceLocation)
        return self
    }

    /// The JSON error code, for a run with `--json`.
    func code() throws -> String { try json()["error"]["code"].string ?? "" }
}

/// A temporary home with Helium (the default browser) and Google Chrome installed.
///
/// - Helium: `Default` "Ryan", `Profile 1` "Work".
/// - Chrome: `Default` "Chrome Ryan", `Profile 1` "Profile 2" (a display name colliding with a
///   directory), `Profile 2` "Work", `Profile 3` "Work" (an ambiguous name).
final class Fixture {
    let temporary: TemporaryHome
    let helium: String
    let chrome: String

    init() throws {
        temporary = try TemporaryHome()
        helium = try temporary.installBrowser(
            .helium, name: "Helium", profiles: [("Default", "Ryan"), ("Profile 1", "Work")])
        chrome = try temporary.installBrowser(
            .chrome, name: "Google Chrome",
            profiles: [
                ("Default", "Chrome Ryan"), ("Profile 1", "Profile 2"), ("Profile 2", "Work"),
                ("Profile 3", "Work"),
            ])
    }

    deinit { temporary.remove() }

    var home: Home { temporary.home }
    var configURL: URL { home.configFile }

    /// Writes config.json with Helium · Default as the default and `rules`.
    func rules(_ rules: JSONValue) throws {
        try config(["browser": .string(helium), "defaultProfile": "Default", "rules": rules])
    }

    func config(_ config: JSONValue) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try writeConfig(try encoder.encode(config))
    }

    func writeConfig(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: configURL)
    }

    func readConfig() throws -> JSONValue { try JSONValue.parse(try Data(contentsOf: configURL)) }

    func configBytes() -> Data { (try? Data(contentsOf: configURL)) ?? Data() }

    /// Writes history entries, oldest first.
    func history(_ entries: [JSONValue]) throws {
        let url = home.historyFile
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data()
        for entry in entries {
            data.append(try encoder.encode(entry))
            data.append(UInt8(ascii: "\n"))
        }
        try data.write(to: url)
    }

    /// Runs the binary with only this fixture's home and browsers in view.
    func run(_ arguments: [String]) throws -> Run {
        let process = Process()
        process.executableURL = try Binary.url()
        process.arguments = arguments
        process.environment = temporary.environment.merging(["PATH": "/usr/bin:/bin"]) { $1 }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(
            status: process.terminationStatus, stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self))
    }

    func json(_ arguments: [String]) throws -> Run { try run(arguments + ["--json"]) }
}

func entry(_ id: String, _ url: String) -> JSONValue {
    [
        "id": .string(id), "time": "2026-10-29T17:04:11Z", "url": .string(url), "source": "default",
        "browser": "/nowhere/Helium.app", "profile": "Default", "result": "launched",
    ]
}

/// Finds the built switchboard-next next to the test binary. The test target depends on the
/// executable target, so `swift test` builds it first.
enum Binary {
    static func url() throws -> URL {
        var folders = [URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()]
        folders += Bundle.allBundles.map { $0.bundleURL.deletingLastPathComponent() }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        folders.append(root.appendingPathComponent(".build/debug"))
        for folder in folders {
            let candidate = folder.appendingPathComponent(Identity.cliName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw FixtureError("Couldn’t find the built \(Identity.cliName) near \(folders.map(\.path)).")
    }
}
