import Foundation

/// The home folder every path hangs off. Binaries build it from `$HOME` through `Env.fromProcess()`;
/// tests from a temporary folder. Nothing in the core finds the real home folder on its own.
public struct Home: Hashable, Sendable {
    public let url: URL

    public init(_ url: URL) {
        self.url = url.standardizedFileURL
    }

    public init(path: String) {
        self.init(URL(fileURLWithPath: path, isDirectory: true))
    }

    public var path: String { url.path }

    public func appending(_ relative: String) -> URL {
        relative.split(separator: "/").reduce(url) { $0.appendingPathComponent(String($1)) }
    }

    /// `~/.config/switchboard-next/config.json`.
    public var configFile: URL { appending(".config/\(Identity.directoryName)/config.json") }

    /// `~/.local/state/switchboard-next/history.jsonl`.
    public var historyFile: URL { appending(".local/state/\(Identity.directoryName)/history.jsonl") }

    /// The current app's config, for importing.
    public var currentAppConfigFile: URL { appending(Identity.currentAppConfig) }

    /// `path` with a leading `~` or `~/` expanded.
    public func expand(_ path: String) -> URL {
        if path == "~" { return url }
        if path.hasPrefix("~/") { return appending(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path)
    }
}

/// The parts of the process environment Switchboard uses, read once by each binary's entry point,
/// so library code never reads the environment itself.
public struct Env: Sendable {
    /// `$SWITCHBOARD_NEXT_APPLICATIONS`, split on `:`: when set, the only folders searched for
    /// browsers. Tests and scenes set it so they never see the machine's real browsers.
    public var applicationDirectories: [URL]?
    /// The other variables Switchboard reads, by name. See `Env.names`.
    public var variables: [String: String]

    public init(applicationDirectories: [URL]? = nil, variables: [String: String] = [:]) {
        self.applicationDirectories = applicationDirectories
        self.variables = variables
    }

    public static let applicationsVariable = "\(Identity.environmentPrefix)_APPLICATIONS"
    public static let configVariable = "\(Identity.environmentPrefix)_CONFIG"
    public static let historyVariable = "\(Identity.environmentPrefix)_HISTORY"

    /// Variables kept in `variables`.
    public static let names = [
        configVariable, historyVariable, "CLAUDE_CONFIG_DIR", "CODEX_HOME", "XDG_CONFIG_HOME",
    ]

    public subscript(name: String) -> String? { variables[name] }

    /// The one place the process environment and `$HOME` are read.
    public static func fromProcess() -> (home: Home?, env: Env) {
        let environment = ProcessInfo.processInfo.environment
        return parse(environment)
    }

    /// `fromProcess` without the process, so the parsing is testable.
    public static func parse(_ environment: [String: String]) -> (home: Home?, env: Env) {
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : Home(path: $0) }
        let applications = environment[applicationsVariable].map { value in
            value.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) }
        }
        var variables: [String: String] = [:]
        for name in names {
            if let value = environment[name], !value.isEmpty { variables[name] = value }
        }
        return (home, Env(applicationDirectories: applications, variables: variables))
    }
}
