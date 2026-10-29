import ArgumentParser
import Foundation

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "List or clear the links Switchboard opened.",
        discussion: """
            URLs are shown without query strings or fragments, which can carry sign-in tokens. Pass an \
            entry to `explain` or `route` with --history <id> or --last instead of copying its URL.
            """,
        subcommands: [HistoryList.self, HistoryClear.self],
        defaultSubcommand: HistoryList.self)
}

struct HistoryEntryReport: Encodable {
    var id: String
    var time: Date
    var url: String
    var source: HistoryEntry.Source
    var rule: HistoryEntry.RuleSnapshot?
    var browser: String
    var browserName: String
    var profile: String
    var profileName: String?
    var result: HistoryEntry.Outcome
    var error: String?

    init(_ entry: HistoryEntry, fullURL: Bool) {
        id = entry.id
        time = entry.time
        url = fullURL ? entry.url : entry.redactedURL
        source = entry.source
        rule = entry.rule
        browser = entry.browser
        browserName = BrowserInfo.displayName(path: entry.browser)
        profile = entry.profile
        profileName = entry.profileName
        result = entry.result
        error = entry.error
    }

    var how: String { rule.map { "rule \($0.index)" } ?? source.rawValue }
    var destination: String { "\(browserName) · \(profileName ?? profile)" }

    var summary: String {
        let rule =
            self.rule.map { "rule \($0.index) (\($0.condition.rawValue) \($0.value))" } ?? source.rawValue
        return "\(rule) → \(destination)"
            + (result == .failed ? ", failed: \(error ?? "unknown error")" : ", launched")
    }
}

struct HistoryList: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List recent links, newest first.")

    @Option(help: "The number of entries to show.")
    var limit = 20

    @Flag(help: "Show URLs in full, including query strings and fragments.")
    var fullUrls = false

    @OptionGroup var global: GlobalOptions

    func validate() throws {
        guard limit > 0 else { throw ValidationError("--limit must be at least 1.") }
    }

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let snapshot = try session.load()
        let entries = try session.historyEntries(snapshot.config).prefix(limit).map {
            HistoryEntryReport($0, fullURL: fullUrls)
        }
        let ages = entries.map { Format.age($0.time, now: context.now) }
        let ageWidth = (ages.map(\.count).max() ?? 0) + 2
        let urlWidth = min(60, entries.map(\.url.count).max() ?? 0) + 2
        var text = entries.isEmpty ? "No links in history yet.\n" : ""
        for (entry, age) in zip(entries, ages) {
            text +=
                "\(entry.id)  \(Format.padded(age, to: ageWidth))\(Format.padded(entry.url, to: urlWidth))\(entry.how) → \(entry.destination)"
                + (entry.result == .failed ? "  (failed: \(entry.error ?? "unknown error"))" : "") + "\n"
        }
        return CommandOutput(
            json: HistoryReport(path: session.historyURL.path, enabled: true, entries: entries), text: text)
    }
}

struct HistoryReport: Encodable {
    var path: String
    var enabled: Bool
    var entries: [HistoryEntryReport]
}

struct HistoryClear: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Delete the history file.",
        discussion: "Works even while history is turned off.")

    @Flag(help: "Show what would be deleted without deleting it.")
    var dryRun = false

    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let count: Int
        do {
            count = try dryRun ? session.history.entries().count : session.history.clear()
        } catch {
            throw OperationError(
                code: .writeFailed, message: "The history couldn’t be cleared. \(error.localizedDescription)")
        }
        let noun = count == 1 ? "entry" : "entries"
        return CommandOutput(
            json: HistoryClearReport(path: session.historyURL.path, entries: count, dryRun: dryRun),
            text: dryRun ? "Would clear \(count) history \(noun).\n" : "Cleared \(count) history \(noun).\n")
    }
}

struct HistoryClearReport: Encodable {
    var path: String
    var entries: Int
    var dryRun: Bool
}
