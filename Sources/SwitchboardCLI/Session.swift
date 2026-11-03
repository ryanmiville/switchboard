import Foundation
import SwitchboardCore

// Per-run state: where the files are, loading and committing the config, and resolving history
// entries. Wraps core's errors in the CLI's codes.

struct Session {
    let context: Context
    let configURL: URL
    let historyURL: URL

    init(context: Context, global: GlobalOptions) {
        self.context = context
        func pick(_ flag: String?, _ variable: String, _ fallback: URL) -> URL {
            (flag ?? context.env[variable]).map(context.home.expand) ?? fallback
        }
        configURL = pick(global.config, Env.configVariable, context.home.configFile)
        historyURL = pick(global.historyFile, Env.historyVariable, context.home.historyFile)
    }

    /// A link to explain or route: typed, or from history.
    struct Linked {
        var url: String
        var entry: History.Entry?
        /// What to show: history URLs are redacted unless --full-urls.
        var display: String
    }

    var store: ConfigStore { ConfigStore(url: configURL) }
    var history: HistoryStore { HistoryStore(url: historyURL) }

    func load() throws(OperationError) -> ConfigStore.Snapshot {
        do {
            return try store.load()
        } catch {
            throw OperationError(error)
        }
    }

    func operations(_ snapshot: ConfigStore.Snapshot) -> RuleOperations {
        RuleOperations(config: snapshot.config, browsers: context.browsers, home: context.home)
    }

    /// Refuses with `conflict` when --if-revision doesn't match the loaded file.
    func check(_ snapshot: ConfigStore.Snapshot, _ change: ChangeOptions) throws(OperationError) {
        guard let expected = change.ifRevision?.lowercased() else { return }
        if expected.count < 8 {
            throw .invalid("Pass the full revision from --json output to --if-revision.")
        }
        if !snapshot.revision.hasPrefix(expected) {
            throw OperationError(
                .conflict,
                "The configuration changed since revision \(Format.short(expected)); it is now \(Format.short(snapshot.revision)). Nothing was written. Look again, then retry."
            )
        }
    }

    /// Saves `config` over the loaded file unless this is a dry run or nothing changed, and returns
    /// the file's revision afterward.
    func commit(_ config: Config, _ snapshot: ConfigStore.Snapshot, dryRun: Bool) throws(OperationError)
        -> String
    {
        if dryRun || config == snapshot.config { return snapshot.revision }
        do {
            return try store.save(config, expecting: snapshot.revision)
        } catch {
            throw OperationError(error)
        }
    }

    func historyEntries(_ config: Config) throws(OperationError) -> [History.Entry] {
        if !config.historyEnabled {
            throw OperationError(
                .historyDisabled,
                "History is turned off (`history on`, or Settings → General). Pass the URL instead.")
        }
        do {
            return try history.entries()
        } catch {
            throw OperationError(.historyUnreadable, "The history file couldn’t be read. \(error.message)")
        }
    }

    /// History that is off or unreadable only means there is nothing to compare against.
    func recentHistory(_ config: Config) -> [History.Entry]? {
        try? historyEntries(config)
    }

    func historyEntry(_ id: String?, _ config: Config) throws(OperationError) -> History.Entry {
        let entries = try historyEntries(config)
        guard let id = id?.lowercased() else {
            guard let first = entries.first else {
                throw OperationError(.historyEntryNotFound, "History is empty. Pass the URL instead.")
            }
            return first
        }
        if let exact = entries.first(where: { $0.id == id }) { return exact }
        if id.count < 4 { throw .invalid("History IDs need at least four characters.") }
        let found = entries.filter { $0.id.hasPrefix(id) || $0.id.hasSuffix(id) }
        if found.count == 1 { return found[0] }
        let candidates = (found.isEmpty ? Array(entries.prefix(10)) : found).map {
            Candidate(id: $0.id, time: $0.time, url: $0.redactedURL)
        }
        if found.isEmpty {
            throw OperationError(
                .historyEntryNotFound, "No history entry matches “\(id)”.", candidates: candidates)
        }
        throw OperationError(
            .ambiguousHistoryEntry, "“\(id)” matches \(found.count) history entries.", candidates: candidates)
    }

    func link(_ link: LinkOptions, _ config: Config) throws(OperationError) -> Linked {
        if let value = link.url {
            guard Link.isWeb(value) || Link.isLocalFile(value) else {
                throw .invalid("“\(value)” isn’t a complete URL. Pass one such as https://example.com/page.")
            }
            return Linked(url: value, entry: nil, display: value)
        }
        let entry = try historyEntry(link.history, config)
        return Linked(url: entry.url, entry: entry, display: link.fullUrls ? entry.url : entry.redactedURL)
    }
}
