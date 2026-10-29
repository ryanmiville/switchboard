import ArgumentParser
import Foundation

struct SwitchboardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "switchboard",
        abstract: "Inspect and change how Switchboard routes links.",
        discussion: """
            Reads and writes the same configuration file as the app, whether or not the app is running. \
            Add --json to any command for one JSON object on stdout, including errors.

            Exit codes: 0 success, 1 failed, 3 not found or ambiguous (nothing changed; candidates are \
            listed), 4 the configuration can't be read or is invalid, 5 the configuration changed since the \
            given or loaded revision, 64 invalid command line.

            Agents: run `switchboard skill show` for the workflow.
            """,
        version: CommandLineTool.bundleVersion(
            executable: Bundle.main.executableURL?.resolvingSymlinksInPath())
            ?? "development",
        subcommands: [
            ExplainCommand.self, RouteCommand.self, RulesCommand.self, DefaultCommand.self,
            ProfilesCommand.self,
            HistoryCommand.self, DoctorCommand.self, SkillCommand.self,
        ])
}

// MARK: - explain

struct ExplainCommand: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explain", abstract: "Show how a URL routes with the current rules, without opening it.")

    @OptionGroup var link: LinkOptions
    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let snapshot = try session.load()
        let link = try session.link(self.link, config: snapshot.config)
        let explanation = session.operations(snapshot).explain(link.url)
        let decision = explanation.decision
        let history = link.entry.map { HistoryEntryReport($0, fullURL: self.link.fullUrls) }
        var text = link.entry == nil ? "" : "URL: \(link.display)\n"
        if let rule = decision.rule {
            text += "Rule \(rule.index) matched: \(Format.rule(rule))\n"
        } else {
            text += "No rule matched; using the default destination.\n"
        }
        text += "  → \(Format.destination(decision.destination))\n"
        if let problem = Format.problem(decision.profileStatus, decision.destination) {
            text += "  ! \(problem)\n"
        }
        if !explanation.alsoMatches.isEmpty {
            text +=
                "Also matches, but never reached: "
                + explanation.alsoMatches.map { "rule \($0.index) (\(Format.rule($0)))" }.joined(
                    separator: ", ") + "\n"
        }
        if let history {
            text += "At the time (\(Format.age(history.time, now: context.now))): \(history.summary)\n"
        }
        return CommandOutput(
            json: ExplainReport(
                url: link.display, matchedRule: decision.rule, destination: decision.destination,
                profileStatus: decision.profileStatus, alsoMatches: explanation.alsoMatches,
                revision: snapshot.revision, history: history),
            text: text)
    }
}

struct ExplainReport: Encodable {
    var url: String
    var matchedRule: RuleReference?
    var destination: DestinationInfo
    var profileStatus: ProfileStatus
    var alsoMatches: [RuleReference]
    var revision: String
    var history: HistoryEntryReport?

    enum CodingKeys: String, CodingKey {
        case url, matchedRule, destination, profileStatus, alsoMatches, revision, history
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(matchedRule, forKey: .matchedRule)
        try container.encode(destination, forKey: .destination)
        try container.encode(profileStatus, forKey: .profileStatus)
        try container.encode(alsoMatches, forKey: .alsoMatches)
        try container.encode(revision, forKey: .revision)
        try container.encodeIfPresent(history, forKey: .history)
    }
}

// MARK: - route

struct RouteCommand: RunnableCommand {
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

    @Option(
        help: "The browser: an app path, bundle identifier, or name. Omit it to inherit the default browser.")
    var browser: String?

    @Option(help: "How the rule matches the URL.")
    var match: Condition = .domain

    @Option(
        help:
            "The pattern. Defaults to the URL's host for domain (pass a parent domain to widen it) and the full URL for exact. Required for contains."
    )
    var value: String?

    @Flag(help: "Add the rule even if it stops later rules from ever matching.")
    var allowShadowing = false

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let snapshot = try session.load()
        try session.check(snapshot, change)
        let link = try session.link(self.link, config: snapshot.config)
        let operations = session.operations(snapshot)
        let result = try operations.route(
            RouteRequest(
                url: link.url, profile: profile, browser: browser, condition: match, value: value,
                allowShadowing: allowShadowing))
        let revision = try session.commit(result.config, over: snapshot, change)
        let edited = RuleOperations(config: result.config, profiles: operations.profiles)
        let before = operations.decision(for: link.url)
        let after = edited.decision(for: link.url)
        let rule = result.index.map(edited.rule(at:))
        let shadowed = result.unreachable.map { edited.reference(at: $0.rule) }
        var text: String
        if let rule, result.changed {
            let verb =
                switch (result.action, change.dryRun) {
                case (.added, true): "Would add"
                case (.added, false): "Added"
                case (_, true): "Would update"
                case (_, false): "Updated"
                }
            text = "\(verb) rule \(rule.index): \(Format.ruleLine(rule))\n"
            text += "  before: \(Format.decision(before))\n  after:  \(Format.decision(after))\n"
            text += Format.unreachable(shadowed) + Format.written(dryRun: change.dryRun, revision: revision)
        } else {
            text = "Nothing to change: the URL already opens in \(Format.decision(before)).\n"
        }
        return CommandOutput(
            json: RouteReport(
                url: link.display, action: result.action, changed: result.changed,
                written: result.changed && !change.dryRun, dryRun: change.dryRun, rule: rule, before: before,
                after: after, shadowedRules: shadowed, revision: revision),
            text: text)
    }
}

struct RouteReport: Encodable {
    var url: String
    var action: RuleChange.Action
    var changed: Bool
    var written: Bool
    var dryRun: Bool
    var rule: RuleInfo?
    var before: DecisionInfo
    var after: DecisionInfo
    var shadowedRules: [RuleReference]
    var revision: String

    enum CodingKeys: String, CodingKey {
        case url, action, changed, written, dryRun, rule, before, after, shadowedRules, revision
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(action, forKey: .action)
        try container.encode(changed, forKey: .changed)
        try container.encode(written, forKey: .written)
        try container.encode(dryRun, forKey: .dryRun)
        try container.encode(rule, forKey: .rule)
        try container.encode(before, forKey: .before)
        try container.encode(after, forKey: .after)
        try container.encode(shadowedRules, forKey: .shadowedRules)
        try container.encode(revision, forKey: .revision)
    }
}

// MARK: - rules

struct RulesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rules",
        abstract: "List and change routing rules by position.",
        discussion: """
            Rules are numbered from 1 in the order they are checked; the first match wins. Positions shift \
            when rules change, so pass --if-revision from the listing to make sure they haven't.
            """,
        subcommands: [RulesList.self, RulesUpdate.self, RulesMove.self, RulesRemove.self],
        defaultSubcommand: RulesList.self)
}

struct DefaultInfo: Encodable {
    var destination: DestinationInfo
    var profileStatus: ProfileStatus
}

struct RulesList: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the rules in order, with each destination and whether it still resolves.")

    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let snapshot = try session.load()
        let operations = session.operations(snapshot)
        let rules = operations.rules()
        let fallback = operations.describe(operations.defaultDestination)
        var text = "Default: \(Format.destination(fallback.info))\n"
        if let problem = Format.problem(fallback.status, fallback.info) { text += "  ! \(problem)\n" }
        if rules.isEmpty { text += "No rules. Every link uses the default destination.\n" }
        let width = min(40, rules.map { max($0.value.count, 1) }.max() ?? 0)
        for rule in rules {
            let pattern = rule.value.isEmpty ? "(empty, ignored)" : rule.value
            text +=
                Format.padded(String(rule.index), to: 3) + Format.padded(rule.condition.rawValue, to: 10)
                + Format.padded(pattern, to: width) + "  → \(Format.destination(rule.destination))"
                + (rule.browser == nil ? "  (default browser)" : "") + "\n"
            if let problem = Format.problem(rule.profileStatus, rule.destination) {
                text += "     ! \(problem)\n"
            }
            if let by = rule.shadowedBy { text += "     ! Never matches: rule \(by) always matches first.\n" }
        }
        text += "Revision \(Format.short(snapshot.revision))\n"
        return CommandOutput(
            json: RulesReport(
                rules: rules,
                default: DefaultInfo(destination: fallback.info, profileStatus: fallback.status),
                revision: snapshot.revision),
            text: text)
    }
}

struct RulesReport: Encodable {
    var rules: [RuleInfo]
    var `default`: DefaultInfo
    var revision: String
}

struct RuleChangeReport: Encodable {
    var action: RuleChange.Action
    var changed: Bool
    var written: Bool
    var dryRun: Bool
    var rule: RuleInfo
    var previous: RuleInfo?
    var from: Int?
    var to: Int?
    var shadowedRules: [RuleReference]
    // False when history is off or unreadable, so no recent links could be checked.
    var historyChecked: Bool
    var historyChanges: [HistoryChangeReport]
    var revision: String
}

struct HistoryChangeReport: Encodable {
    var id: String
    var url: String
    var before: DecisionInfo
    var after: DecisionInfo
}

extension Session {
    func historyChanges(_ operations: RuleOperations, to edited: Config) -> (
        checked: Bool, changes: [HistoryChangeReport]
    ) {
        guard let entries = recentHistory(operations.config) else { return (false, []) }
        return (
            true,
            operations.historyChanges(to: edited, entries: entries).map {
                HistoryChangeReport(
                    id: $0.entry.id, url: $0.entry.redactedURL, before: $0.before, after: $0.after)
            }
        )
    }

    // Shared by the position-based rule commands.
    func ruleChange(
        _ result: RuleChange, from operations: RuleOperations, snapshot: ConfigStore.Snapshot,
        options: ChangeOptions,
        rule: RuleInfo, previous: RuleInfo? = nil, from: Int? = nil, to: Int? = nil
    ) throws -> (report: RuleChangeReport, footer: String) {
        let revision = try commit(result.config, over: snapshot, options)
        let edited = RuleOperations(config: result.config, profiles: operations.profiles)
        let shadowed = result.unreachable.map { edited.reference(at: $0.rule) }
        let history = historyChanges(operations, to: result.config)
        let report = RuleChangeReport(
            action: result.action, changed: result.changed, written: result.changed && !options.dryRun,
            dryRun: options.dryRun, rule: rule, previous: previous, from: from, to: to,
            shadowedRules: shadowed,
            historyChecked: history.checked, historyChanges: history.changes, revision: revision)
        let footer =
            Format.unreachable(shadowed) + Format.historyChanges(history.changes, checked: history.checked)
            + Format.written(dryRun: options.dryRun, revision: revision)
        return (report, footer)
    }
}

struct RulesUpdate: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update", abstract: "Change a rule's destination or pattern.")

    @Argument(help: "The rule's position, as `switchboard rules list` shows it.")
    var position: Int

    @Option(help: "The profile, resolved in the rule's browser after any browser change.")
    var profile: String?

    @Option(
        help: "Give the rule its own browser: an app path, bundle identifier, or name. Requires --profile.")
    var browser: String?

    @Flag(help: "Make the rule inherit the default browser. Requires --profile.")
    var defaultBrowser = false

    @Option(help: "How the rule matches the URL.")
    var match: Condition?

    @Option(help: "The pattern.")
    var value: String?

    @Flag(help: "Change the rule even if it stops later rules from ever matching.")
    var allowShadowing = false

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions

    func validate() throws {
        if browser != nil && defaultBrowser {
            throw ValidationError("Pass --browser or --default-browser, not both.")
        }
        if (browser != nil || defaultBrowser) && profile == nil {
            throw ValidationError(
                "Changing a rule's browser needs --profile: profile identifiers belong to one browser.")
        }
    }

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let snapshot = try session.load()
        try session.check(snapshot, change)
        let operations = session.operations(snapshot)
        let result = try operations.updateRule(
            at: position,
            RuleUpdate(
                profile: profile,
                browser: defaultBrowser ? .defaultBrowser : browser.map(RuleUpdate.BrowserChoice.browser),
                condition: match, value: value, allowShadowing: allowShadowing))
        let previous = operations.rule(at: position - 1)
        let rule = RuleOperations(config: result.config, profiles: operations.profiles).rule(at: position - 1)
        let output = try session.ruleChange(
            result, from: operations, snapshot: snapshot, options: change, rule: rule, previous: previous)
        let text =
            result.changed
            ? "\(change.dryRun ? "Would update" : "Updated") rule \(rule.index): \(Format.ruleLine(rule))\n  was: \(Format.ruleLine(previous))\n"
                + output.footer
            : "Nothing to change: rule \(rule.index) is already \(Format.ruleLine(rule)).\n"
        return CommandOutput(json: output.report, text: text)
    }
}

struct RulesMove: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move", abstract: "Move a rule to another position.")

    @Argument(help: "The rule's current position.")
    var from: Int

    @Argument(help: "The position it should have afterward.")
    var to: Int

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let snapshot = try session.load()
        try session.check(snapshot, change)
        let operations = session.operations(snapshot)
        let result = try operations.moveRule(from: from, to: to)
        let rule = RuleOperations(config: result.config, profiles: operations.profiles).rule(at: to - 1)
        let output = try session.ruleChange(
            result, from: operations, snapshot: snapshot, options: change, rule: rule, from: from, to: to)
        let text =
            result.changed
            ? "\(change.dryRun ? "Would move" : "Moved") rule \(from) to position \(to): \(Format.ruleLine(rule))\n"
                + output.footer
            : "Nothing to change: rule \(from) is already at position \(to).\n"
        return CommandOutput(json: output.report, text: text)
    }
}

struct RulesRemove: RunnableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a rule.")

    @Argument(help: "The rule's position.")
    var position: Int

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let snapshot = try session.load()
        try session.check(snapshot, change)
        let operations = session.operations(snapshot)
        let result = try operations.removeRule(at: position)
        let rule = operations.rule(at: position - 1)
        let output = try session.ruleChange(
            result, from: operations, snapshot: snapshot, options: change, rule: rule)
        let text =
            "\(change.dryRun ? "Would remove" : "Removed") rule \(rule.index): \(Format.ruleLine(rule))\n"
            + output.footer
        return CommandOutput(json: output.report, text: text)
    }
}

// MARK: - default

struct DefaultCommand: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "default",
        abstract: "Show or change the destination for links that match no rule.",
        discussion: """
            Changing the default browser needs --profile, and is refused (exit 3) while rules inherit the \
            default browser: their profiles were chosen in the old browser. Give those rules an explicit \
            browser with `switchboard rules update` first.
            """)

    @Option(help: "The default browser: an app path, bundle identifier, or name.")
    var browser: String?

    @Option(help: "The default profile, resolved in the default browser.")
    var profile: String?

    @OptionGroup var change: ChangeOptions
    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let snapshot = try session.load()
        let operations = session.operations(snapshot)
        let current = operations.describe(operations.defaultDestination)
        let currentInfo = DefaultInfo(destination: current.info, profileStatus: current.status)
        guard browser != nil || profile != nil else {
            var text = "Default: \(Format.destination(current.info))\n"
            if let problem = Format.problem(current.status, current.info) { text += "  ! \(problem)\n" }
            return CommandOutput(
                json: DefaultReport(
                    destination: current.info, profileStatus: current.status, revision: snapshot.revision),
                text: text)
        }
        try session.check(snapshot, change)
        let result = try operations.setDefault(browser: browser, profile: profile)
        let revision = try session.commit(result.config, over: snapshot, change)
        let edited = RuleOperations(config: result.config, profiles: operations.profiles)
        let updated = edited.describe(edited.defaultDestination)
        let history = session.historyChanges(operations, to: result.config)
        let text =
            result.changed
            ? "\(change.dryRun ? "Would change" : "Changed") the default to \(Format.destination(updated.info))\n  was: \(Format.destination(current.info))\n"
                + Format.historyChanges(history.changes, checked: history.checked)
                + Format.written(dryRun: change.dryRun, revision: revision)
            : "Nothing to change: the default is already \(Format.destination(current.info)).\n"
        return CommandOutput(
            json: DefaultChangeReport(
                changed: result.changed, written: result.changed && !change.dryRun, dryRun: change.dryRun,
                before: currentInfo, destination: updated.info, profileStatus: updated.status,
                historyChecked: history.checked, historyChanges: history.changes, revision: revision),
            text: text)
    }
}

struct DefaultReport: Encodable {
    var destination: DestinationInfo
    var profileStatus: ProfileStatus
    var revision: String
}

struct DefaultChangeReport: Encodable {
    var changed: Bool
    var written: Bool
    var dryRun: Bool
    var before: DefaultInfo
    var destination: DestinationInfo
    var profileStatus: ProfileStatus
    var historyChecked: Bool
    var historyChanges: [HistoryChangeReport]
    var revision: String
}

// MARK: - profiles

struct ProfilesCommand: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profiles", abstract: "List installed, supported Chromium browsers and their profiles.")

    @Option(help: "Only list this browser: an app path, bundle identifier, or name.")
    var browser: String?

    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        let snapshot = try session.load()
        let operations = session.operations(snapshot)
        let browsers = try browser.map { [try operations.resolveBrowser($0)] } ?? operations.browsers()
        let defaultBrowser = BrowserInfo.standardized(snapshot.config.browser)
        let reports = browsers.map { info in
            var report = BrowserReport(
                name: info.name, path: info.path, bundleIdentifier: info.bundleIdentifier,
                isDefault: info.path == defaultBrowser,
                localState: operations.catalog.profileStore.localStateURL(browserPath: info.path)?.path,
                profiles: [])
            do {
                report.profiles = try operations.profiles.profiles(in: info.path).map {
                    ProfileReport(profile: $0.directory, profileName: $0.name)
                }
            } catch {
                report.error = error.localizedDescription
            }
            return report
        }
        var text =
            reports.isEmpty
            ? "No supported Chromium browsers found in /Applications or ~/Applications.\n" : ""
        for report in reports {
            text +=
                "\(report.name)\(report.isDefault ? " (default browser)" : "")  \(report.path)  (\(report.bundleIdentifier))\n"
            if let error = report.error { text += "  ! \(error)\n" }
            let width = (report.profiles.map(\.profile.count).max() ?? 0) + 2
            for profile in report.profiles {
                text += "  \(Format.padded(profile.profile, to: width))\(profile.profileName)\n"
            }
        }
        return CommandOutput(json: ProfilesReport(browsers: reports), text: text)
    }
}

struct ProfilesReport: Encodable {
    var browsers: [BrowserReport]
}

struct BrowserReport: Encodable {
    var name: String
    var path: String
    var bundleIdentifier: String
    var isDefault: Bool
    var localState: String?
    var profiles: [ProfileReport]
    var error: String? = nil
}

struct ProfileReport: Encodable {
    var profile: String
    var profileName: String
}
