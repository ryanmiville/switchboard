import ArgumentParser
import SwitchboardCore

// The command line, as ArgumentParser definitions. Behaviour lives in Commands/. The commands are
// only parsed here; CommandLineTool runs them with a Session, so nothing reads the process.

/// The CLI's version, shown by `--version` and `doctor`.
public let cliVersion = "0.2.0"

struct Root: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: Identity.cliName,
        abstract: "Inspect and change how \(Identity.appName) routes links.",
        discussion: """
            Reads and writes the same configuration file as the app, whether or not the app is \
            running. It never opens links. Add --json to any command for one JSON object on stdout, \
            including errors.

            Exit codes: 0 success, 1 failed, 2 invalid command line, 3 not found or ambiguous \
            (nothing changed; candidates are listed), 4 the configuration can't be read or is invalid, \
            5 the configuration changed since the given or loaded revision.

            Agents: run `\(Identity.cliName) skill show` for the workflow.
            """,
        version: cliVersion,
        subcommands: [
            ExplainCommand.self, RouteCommand.self, RulesCommand.self, DefaultCommand.self,
            ProfilesCommand.self,
            HistoryCommand.self, PickerCommand.self, ConfigCommand.self, DoctorCommand.self,
            SkillCommand.self,
        ])
}

/// Options every command takes. They may appear anywhere on the command line.
struct GlobalOptions: ParsableArguments {
    @Flag(help: "Print one JSON object on stdout, including errors.")
    var json = false

    @Option(
        help: ArgumentHelp(
            "The configuration file. Defaults to $\(Env.configVariable), then ~/.config/\(Identity.directoryName)/config.json.",
            valueName: "path"))
    var config: String?

    @Option(
        name: .customLong("history-file"),
        help: ArgumentHelp(
            "The history file. Defaults to $\(Env.historyVariable), then ~/.local/state/\(Identity.directoryName)/history.jsonl.",
            valueName: "path"))
    var historyFile: String?

    /// The global options' names, which CommandLineTool moves after the subcommand.
    static let flags: Set<String> = ["--json"]
    static let options: Set<String> = ["--config", "--history-file"]
}

/// Which link a command is about: typed, or from history.
struct LinkOptions: ParsableArguments {
    @Argument(help: "A complete URL, such as https://github.com/acme/api.")
    var url: String?

    @Option(
        help: ArgumentHelp(
            "Use a history entry: its ID, or four or more characters from its start or end.", valueName: "id")
    )
    var history: String?

    @Flag(help: "Use the most recent history entry.")
    var last = false

    @Flag(help: "Show URLs from history in full instead of hiding query strings and fragments.")
    var fullUrls = false

    func check() throws {
        let given = [url != nil, history != nil, last].filter { $0 }.count
        if given == 0 { throw ValidationError("Pass a URL, --history <id>, or --last.") }
        if given > 1 { throw ValidationError("Pass only one of a URL, --history <id>, or --last.") }
    }
}

/// Options of every command that writes the configuration.
struct ChangeOptions: ParsableArguments {
    @Flag(help: "Show the change without writing it.")
    var dryRun = false

    @Option(
        help: ArgumentHelp(
            "Exit 5 without writing unless the configuration still has this revision, from any --json output.",
            valueName: "revision"))
    var ifRevision: String?
}

enum Match: String, ExpressibleByArgument, CaseIterable {
    case domain, contains, exact

    var condition: Condition {
        switch self {
        case .domain: .domain
        case .contains: .contains
        case .exact: .exact
        }
    }
}

struct ExplainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explain", abstract: "Show how a URL routes with the current rules, without opening it.")

    @OptionGroup var link: LinkOptions
    @OptionGroup var global: GlobalOptions

    func validate() throws { try link.check() }
}

struct RouteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "route",
        abstract: "Make a URL open in a browser profile by adding or updating one rule.",
        discussion: """
            If the URL already opens there, nothing changes. A rule with the same match and pattern is \
            updated in place; otherwise the new rule goes immediately before the rule that matches the URL \
            now, or last if only the default matched. The change is checked with the router before it is \
            written, and refused if it would stop a later rule from ever matching.
            """)

    @OptionGroup var link: LinkOptions

    @Option(
        help: "The profile: a directory identifier such as \"Profile 2\", or an unambiguous display name.")
    var profile: String

    @Option(help: "The browser: a path, id, or name. Omit it to inherit the default browser.")
    var browser: String?

    @Option(name: .customLong("match"), help: "How the rule matches the URL.")
    var condition: Match = .domain

    @Option(
        help: """
            The pattern. Defaults to the URL's host for domain (pass a parent domain to widen it) and the full \
            URL for exact. Required for contains.
            """)
    var value: String?

    @Flag(help: "Add the rule even if it stops later rules from ever matching.")
    var allowShadowing = false

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions

    func validate() throws { try link.check() }
}

struct RulesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rules", abstract: "List and change routing rules by position.",
        discussion: """
            Rules are numbered from 1 in the order they are checked; the first match wins. Positions shift \
            when rules change, so pass --if-revision from the listing to make sure they haven't.
            """,
        subcommands: [RulesList.self, RulesUpdate.self, RulesMove.self, RulesRemove.self])
}

struct RulesList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the rules in order, with each destination and whether it still resolves.")

    @OptionGroup var global: GlobalOptions
}

struct RulesUpdate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update", abstract: "Change a rule's destination or pattern.")

    @Argument(help: "The rule's position, as `rules list` shows it.")
    var position: Int

    @Option(help: "The profile, resolved in the rule's browser after any browser change.")
    var profile: String?

    @Option(help: "Give the rule its own browser: a path, id, or name. Requires --profile.")
    var browser: String?

    @Flag(help: "Make the rule inherit the default browser. Requires --profile.")
    var defaultBrowser = false

    @Option(name: .customLong("match"), help: "How the rule matches the URL.")
    var condition: Match?

    @Option(help: "The pattern.")
    var value: String?

    @Flag(help: "Change the rule even if it stops later rules from ever matching.")
    var allowShadowing = false

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions

    func validate() throws {
        if browser != nil && defaultBrowser {
            throw ValidationError("--browser can't be used with --default-browser.")
        }
        if (browser != nil || defaultBrowser) && profile == nil {
            throw ValidationError(
                "\(browser != nil ? "--browser" : "--default-browser") requires --profile: profile identifiers belong to one browser."
            )
        }
    }
}

struct RulesMove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move", abstract: "Move a rule to another position.")

    @Argument(help: "The rule's current position.")
    var from: Int

    @Argument(help: "The position it should have afterward.")
    var to: Int

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions
}

struct RulesRemove: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a rule.")

    @Argument(help: "The rule's position.")
    var position: Int

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions
}

struct DefaultCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "default", abstract: "Show or change the destination for links that match no rule.",
        discussion: """
            Changing the default browser needs --profile, and is refused (exit 3) while rules inherit the \
            default browser: their profiles were chosen in the old browser. Give those rules an explicit \
            browser with `rules update` first.
            """)

    @Option(help: "The default browser: a path, id, or name.")
    var browser: String?

    @Option(help: "The default profile, resolved in the default browser.")
    var profile: String?

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions
}

struct ProfilesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profiles", abstract: "List installed, supported Chromium browsers and their profiles.")

    @Option(help: "Only list this browser: a path, id, or name.")
    var browser: String?

    @OptionGroup var global: GlobalOptions
}

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "List, clear, or turn on and off the history of links Switchboard opened.",
        discussion: """
            URLs are shown without query strings or fragments, which can carry sign-in tokens. Pass an entry \
            to `explain` or `route` with --history <id> or --last instead of copying its URL.
            """,
        subcommands: [HistoryList.self, HistoryClear.self, HistoryOn.self, HistoryOff.self],
        defaultSubcommand: HistoryList.self)
}

struct HistoryList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List recent links, newest first (the default).")

    @Option(help: "The number of entries to show.")
    var limit = 20

    @Flag(help: "Show URLs in full, including query strings and fragments.")
    var fullUrls = false

    @OptionGroup var global: GlobalOptions

    func validate() throws {
        if limit < 1 { throw ValidationError("--limit must be at least 1.") }
    }
}

struct HistoryClear: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear", abstract: "Delete the history file. Works even while history is off.")

    @Flag(help: "Show what would be deleted without deleting it.")
    var dryRun = false

    @OptionGroup var global: GlobalOptions
}

struct HistoryOn: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "on", abstract: "Start recording opened links (the default).")

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions
}

struct HistoryOff: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "off", abstract: "Stop recording opened links. Existing history is kept until cleared.")

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions
}

struct PickerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "picker",
        abstract: "Show and change the Quick Switch picker: its shortcut and destinations.",
        subcommands: [
            PickerShow.self, PickerShortcut.self, PickerDestination.self, PickerShowAll.self,
        ])
}

struct PickerShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show the picker's shortcut and which destinations it shows.")

    @OptionGroup var global: GlobalOptions
}

struct PickerShortcut: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shortcut",
        abstract: "Set the global shortcut that opens the picker, such as ctrl+alt+space.")

    @Argument var shortcut: String
    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions
}

struct PickerDestination: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "destination", abstract: "Show or hide a destination in the picker.")

    @Option(help: "The browser: a path, id, or name.")
    var browser: String

    @Option(help: "The profile, resolved in that browser.")
    var profile: String

    @Flag(help: "Hide it instead of showing it.")
    var hide = false

    @Flag(help: "Show only this destination, hiding every other one. Add more with `destination` after.")
    var only = false

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions

    func validate() throws {
        if hide && only { throw ValidationError("--hide can't be used with --only.") }
    }
}

struct PickerShowAll: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show-all", abstract: "Show every installed destination again.")

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions
}

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config", abstract: "Show the whole configuration, its path, and its revision.")

    @OptionGroup var global: GlobalOptions
}

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check the configuration, browsers, profiles, and history. Changes nothing.")

    @OptionGroup var global: GlobalOptions
}

struct SkillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skill", abstract: "Install and manage the agent skill that teaches this workflow.",
        subcommands: [SkillSetup.self, SkillStatus.self, SkillRemove.self, SkillShow.self])
}

extension Agent: ExpressibleByArgument {}

struct SkillSetup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup", abstract: "Install or update the skill for each agent found. Safe to repeat.")

    @Option(help: "Only this agent.")
    var agent: Agent?

    @Flag(help: "Show what would change without changing it.")
    var dryRun = false

    @OptionGroup var global: GlobalOptions
}

struct SkillStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Report each skill as current, outdated, missing, or foreign.")

    @Option(help: "Only this agent.")
    var agent: Agent?

    @OptionGroup var global: GlobalOptions
}

struct SkillRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove", abstract: "Remove the skills that setup installed.")

    @Option(help: "Only this agent.")
    var agent: Agent?

    @Flag(help: "Show what would change without changing it.")
    var dryRun = false

    @OptionGroup var global: GlobalOptions
}

struct SkillShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show", abstract: "Print the routing guide for agents.")

    @OptionGroup var global: GlobalOptions
}
