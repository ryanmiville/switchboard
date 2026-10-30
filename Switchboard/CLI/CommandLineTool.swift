import ArgumentParser
import Foundation

// Everything a command reads from its environment, so tests can run commands in-process against
// temporary files without touching personal configuration.
struct CommandContext {
    var environment: [String: String]
    var homeDirectory: URL
    // nil scans /Applications and ~/Applications.
    var applicationDirectories: [URL]? = nil
    var executableURL: URL?
    var installedApp = URL(fileURLWithPath: "/Applications/Switchboard.app")
    var now = Date()
    var stdoutIsTerminal = false

    static func current() -> CommandContext {
        let environment = ProcessInfo.processInfo.environment
        return CommandContext(
            environment: environment,
            homeDirectory: environment["HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser,
            executableURL: Bundle.main.executableURL?.resolvingSymlinksInPath(),
            stdoutIsTerminal: isatty(STDOUT_FILENO) == 1)
    }

    func path(_ value: String) -> URL {
        if value == "~" { return homeDirectory }
        if value.hasPrefix("~/") { return homeDirectory.appendingPathComponent(String(value.dropFirst(2))) }
        return URL(fileURLWithPath: value)
    }
}

struct CommandOutput {
    var json: any Encodable
    var text: String
}

protocol RunnableCommand: ParsableCommand {
    func run(in context: CommandContext) throws -> CommandOutput
}

public enum CommandLineTool {
    public static func main() -> Never {
        let outcome = run(Array(CommandLine.arguments.dropFirst()), context: .current())
        FileHandle.standardOutput.write(Data(outcome.stdout.utf8))
        FileHandle.standardError.write(Data(outcome.stderr.utf8))
        exit(outcome.status)
    }

    struct Outcome {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    static func run(_ arguments: [String], context: CommandContext) -> Outcome {
        let json = arguments.contains("--json")
        let command: ParsableCommand
        do {
            command = try SwitchboardCommand.parseAsRoot(arguments)
        } catch {
            return parserFailure(error, json: json, terminal: context.stdoutIsTerminal)
        }
        guard let runnable = command as? any RunnableCommand else {
            // Help, and command groups without a default, print their help by throwing from run().
            do {
                var command = command
                try command.run()
                return Outcome(status: 0, stdout: "", stderr: "")
            } catch {
                return parserFailure(error, json: json, terminal: context.stdoutIsTerminal)
            }
        }
        do {
            let output = try runnable.run(in: context)
            return Outcome(
                status: 0,
                stdout: json ? encode(output.json, terminal: context.stdoutIsTerminal) : output.text,
                stderr: "")
        } catch let error as OperationError {
            return failure(error, json: json, terminal: context.stdoutIsTerminal)
        } catch let error as ConfigStoreError {
            return failure(OperationError(error), json: json, terminal: context.stdoutIsTerminal)
        } catch {
            return parserFailure(error, json: json, terminal: context.stdoutIsTerminal)
        }
    }

    // Help, usage errors (exit 64), and unexpected failures (exit 1).
    private static func parserFailure(_ error: Error, json: Bool, terminal: Bool) -> Outcome {
        let status = SwitchboardCommand.exitCode(for: error).rawValue
        let message = SwitchboardCommand.fullMessage(for: error)
        if status == 0 { return Outcome(status: 0, stdout: message + "\n", stderr: "") }
        guard json else { return Outcome(status: status, stdout: "", stderr: message + "\n") }
        let code = status == 64 ? OperationError.Code.invalidArgument.rawValue : "failed"
        let summary = SwitchboardCommand.message(for: error)
        return Outcome(
            status: status,
            stdout: encode(
                ErrorReport(error: .init(code: code, message: summary, candidates: [])), terminal: terminal),
            stderr: "")
    }

    private static func failure(_ error: OperationError, json: Bool, terminal: Bool) -> Outcome {
        if json {
            return Outcome(
                status: error.code.exitCode,
                stdout: encode(
                    ErrorReport(
                        error: .init(
                            code: error.code.rawValue, message: error.message, candidates: error.candidates)),
                    terminal: terminal),
                stderr: "")
        }
        var text = "error: \(error.message)\n"
        for candidate in error.candidates { text += Format.candidate(candidate) }
        return Outcome(status: error.code.exitCode, stdout: "", stderr: text)
    }

    // Indented for people at a terminal, one line for programs reading a pipe.
    static func encode(_ value: any Encodable, terminal: Bool) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting =
            terminal
            ? [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data =
            (try? encoder.encode(value))
            ?? Data(
                #"{"error":{"code":"failed","message":"Output couldn’t be encoded.","candidates":[]}}"#.utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // The version of the app bundle that contains this tool, or nil for development builds.
    static func bundleVersion(executable: URL?) -> String? {
        guard let executable else { return nil }
        let components = executable.pathComponents
        guard components.count > 3, components[components.count - 2] == "Helpers",
            components[components.count - 3] == "Contents", components[components.count - 4].hasSuffix(".app")
        else { return nil }
        return appVersion(
            executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }

    static func appVersion(_ app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let version = info["CFBundleShortVersionString"] as? String
        else { return nil }
        return (info["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
    }
}

struct ErrorReport: Encodable {
    struct Body: Encodable {
        var code: String
        var message: String
        var candidates: [Candidate]
    }

    var error: Body
}

// MARK: - Shared options

struct GlobalOptions: ParsableArguments {
    @Flag(help: "Print one JSON object on stdout, including errors.")
    var json = false

    @Option(
        help: ArgumentHelp(
            "The configuration file. Defaults to $SWITCHBOARD_CONFIG, then ~/.config/switchboard/config.json.",
            valueName: "path"))
    var config: String?

    @Option(
        name: .customLong("history-file"),
        help: ArgumentHelp(
            "The history file. Defaults to $SWITCHBOARD_HISTORY, then ~/.local/state/switchboard/history.jsonl.",
            valueName: "path"))
    var historyFile: String?
}

struct ChangeOptions: ParsableArguments {
    @Flag(help: "Show the change without writing it.")
    var dryRun = false

    @Option(
        name: .customLong("if-revision"),
        help: ArgumentHelp(
            "Exit 5 without writing unless the configuration still has this revision, from any --json output.",
            valueName: "revision"))
    var ifRevision: String?
}

struct LinkOptions: ParsableArguments {
    @Argument(help: "A complete URL, such as https://github.com/acme/api.")
    var url: String?

    @Option(
        name: .customLong("history"),
        help: ArgumentHelp(
            "Use a history entry: its ID, or the last four or more characters of it.", valueName: "id"))
    var historyID: String?

    @Flag(help: "Use the most recent history entry.")
    var last = false

    @Flag(help: "Show URLs from history in full instead of hiding query strings and fragments.")
    var fullUrls = false

    func validate() throws {
        guard [url != nil, historyID != nil, last].filter({ $0 }).count == 1 else {
            throw ValidationError("Pass exactly one of a URL, --history <id>, or --last.")
        }
    }
}

extension Condition: ExpressibleByArgument {}

// MARK: - Per-command state

// Resolves file locations and wraps the shared operations with the CLI's error codes.
struct Session {
    let context: CommandContext
    let configURL: URL
    let historyURL: URL

    init(_ context: CommandContext, _ options: GlobalOptions) {
        self.context = context
        configURL =
            (options.config ?? context.environment["SWITCHBOARD_CONFIG"]).map(context.path)
            ?? Config.path(home: context.homeDirectory)
        historyURL =
            (options.historyFile ?? context.environment["SWITCHBOARD_HISTORY"]).map(context.path)
            ?? HistoryStore.location(home: context.homeDirectory)
    }

    var store: ConfigStore { ConfigStore(url: configURL) }
    var history: HistoryStore { HistoryStore(url: historyURL) }
    var catalog: BrowserCatalog {
        BrowserCatalog(
            homeDirectory: context.homeDirectory, applicationDirectories: context.applicationDirectories)
    }

    func load() throws -> ConfigStore.Snapshot {
        do {
            return try store.load()
        } catch let error as ConfigStoreError {
            throw OperationError(error)
        }
    }

    func operations(_ snapshot: ConfigStore.Snapshot) -> RuleOperations {
        RuleOperations(config: snapshot.config, catalog: catalog)
    }

    func check(_ snapshot: ConfigStore.Snapshot, _ options: ChangeOptions) throws {
        guard let expected = options.ifRevision?.lowercased() else { return }
        guard expected.count >= 8 else {
            throw OperationError.invalidArgument(
                "Pass the full revision from --json output to --if-revision.")
        }
        guard snapshot.revision.hasPrefix(expected) else {
            throw OperationError(
                code: .conflict,
                message:
                    "The configuration changed since revision \(Format.short(expected)); it is now \(Format.short(snapshot.revision)). Nothing was written. Look at the rules again, then retry."
            )
        }
    }

    // Returns the revision the file has afterward.
    func commit(_ config: Config, over snapshot: ConfigStore.Snapshot, _ options: ChangeOptions) throws
        -> String
    {
        guard !options.dryRun, config != snapshot.config else { return snapshot.revision }
        do {
            return try store.save(config, expecting: snapshot.revision)
        } catch let error as ConfigStoreError {
            throw OperationError(error)
        } catch {
            throw OperationError(
                code: .writeFailed,
                message:
                    "The configuration couldn’t be saved. Nothing was changed. \(error.localizedDescription)")
        }
    }

    func historyEntries(_ config: Config) throws -> [HistoryEntry] {
        guard config.historyEnabled else {
            throw OperationError(
                code: .historyDisabled,
                message:
                    "History is turned off (Settings → General, or \"history\": {\"enabled\": false} in the configuration). Pass the URL instead."
            )
        }
        do {
            return try history.entries()
        } catch {
            throw OperationError(
                code: .historyUnreadable,
                message: "The history file couldn’t be read. \(error.localizedDescription)")
        }
    }

    // History that is off or unreadable only means there is nothing to compare against.
    func recentHistory(_ config: Config) -> [HistoryEntry]? {
        try? historyEntries(config)
    }

    func historyEntry(id: String?, config: Config) throws -> HistoryEntry {
        let entries = try historyEntries(config)
        guard let id = id?.lowercased() else {
            guard let latest = entries.first else {
                throw OperationError(
                    code: .historyEntryNotFound, message: "History is empty. Pass the URL instead.")
            }
            return latest
        }
        if let exact = entries.first(where: { $0.id == id }) { return exact }
        guard id.count >= 4 else {
            throw OperationError.invalidArgument("History IDs need at least four characters.")
        }
        let matches = entries.filter { $0.id.hasSuffix(id) || $0.id.hasPrefix(id) }
        if matches.count == 1 { return matches[0] }
        let candidates = (matches.isEmpty ? Array(entries.prefix(10)) : matches).map {
            Candidate(id: $0.id, time: $0.time, url: $0.redactedURL)
        }
        if matches.isEmpty {
            throw OperationError(
                code: .historyEntryNotFound, message: "No history entry matches “\(id)”.",
                candidates: candidates)
        }
        throw OperationError(
            code: .ambiguousHistoryEntry, message: "“\(id)” matches \(matches.count) history entries.",
            candidates: candidates)
    }

    struct Link {
        var url: URL
        var entry: HistoryEntry?
        var display: String
    }

    func link(_ options: LinkOptions, config: Config) throws -> Link {
        if let value = options.url {
            guard let url = URL(string: value), Router.isWebURL(url) || Router.isLocalFileURL(url) else {
                throw OperationError.invalidArgument(
                    "“\(value)” isn’t a complete URL. Pass one such as https://example.com/page.")
            }
            return Link(url: url, entry: nil, display: value)
        }
        let entry = try historyEntry(id: options.historyID, config: config)
        guard let url = URL(string: entry.url) else {
            throw OperationError(
                code: .historyUnreadable, message: "History entry \(entry.id) has no valid URL.")
        }
        return Link(url: url, entry: entry, display: options.fullUrls ? entry.url : entry.redactedURL)
    }
}
