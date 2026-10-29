import ArgumentParser
import Foundation

// Installs a short SKILL.md that points agents at `switchboard skill show`, so upgrading Switchboard
// updates the guide they follow.
struct SkillInstaller {
    enum Agent: String, CaseIterable, ExpressibleByArgument {
        case claude, codex, opencode, pi
    }

    enum State: String, Encodable {
        // status
        case current, outdated, missing, foreign
        // setup and remove
        case installed, updated, unchanged, removed
    }

    struct Item: Encodable, Equatable {
        var agents: [Agent]
        var path: String
        var status: State
    }

    var home: URL
    var environment: [String: String]

    static let marker =
        "<!-- switchboard-skill: installed by `switchboard skill setup`; `switchboard skill remove` deletes it. -->"

    static let content = """
        ---
        name: switchboard
        description: Fix which browser and profile links open in on this Mac with the switchboard CLI. Use when the user says a link opened in the wrong browser or profile, or asks to send a site to a particular browser profile.
        ---
        \(marker)

        # Switchboard

        Before changing how links are routed, run `switchboard skill show` and follow that guide. It ships with the installed Switchboard, so it always matches this version of the CLI.

        Never edit `~/.config/switchboard/config.json` by hand.

        """

    private func directory(_ variable: String, default path: String) -> URL {
        environment[variable].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(path)
    }

    // Agents are found by their configuration directories.
    func isPresent(_ agent: Agent) -> Bool {
        let directory =
            switch agent {
            case .claude: directory("CLAUDE_CONFIG_DIR", default: ".claude")
            case .codex: directory("CODEX_HOME", default: ".codex")
            case .opencode:
                directory("XDG_CONFIG_HOME", default: ".config").appendingPathComponent("opencode")
            case .pi: home.appendingPathComponent(".pi")
            }
        return FileManager.default.fileExists(atPath: directory.path)
    }

    func skillURL(for agent: Agent) -> URL {
        let root =
            switch agent {
            case .claude: directory("CLAUDE_CONFIG_DIR", default: ".claude")
            case .codex where environment["CODEX_HOME"]?.isEmpty == false:
                directory("CODEX_HOME", default: ".codex")
            case .codex, .opencode, .pi: home.appendingPathComponent(".agents")
            }
        return root.appendingPathComponent("skills/switchboard/SKILL.md")
    }

    // Agents that share a location appear once.
    func locations(_ agents: [Agent]) -> [(agents: [Agent], url: URL)] {
        var result: [(agents: [Agent], url: URL)] = []
        for agent in agents {
            let url = skillURL(for: agent)
            if let index = result.firstIndex(where: { $0.url == url }) {
                result[index].agents.append(agent)
            } else {
                result.append(([agent], url))
            }
        }
        return result
    }

    func state(at url: URL) -> State {
        guard let data = FileManager.default.contents(atPath: url.path) else { return .missing }
        let text = String(decoding: data, as: UTF8.self)
        // Any version of the marker means setup installed it.
        guard text.contains("<!-- switchboard-skill") else { return .foreign }
        return text == Self.content ? .current : .outdated
    }

    // Detected agents, plus any location that already holds a Switchboard skill.
    func status(agent: Agent?) -> [Item] {
        let agents = agent.map { [$0] } ?? Agent.allCases
        return locations(agents).compactMap { location in
            let present = agent == nil ? location.agents.filter(isPresent) : location.agents
            let state = state(at: location.url)
            guard !present.isEmpty || state != .missing else { return nil }
            return Item(
                agents: present.isEmpty ? location.agents : present, path: location.url.path, status: state)
        }
    }

    func setup(agent: Agent?, dryRun: Bool) throws -> [Item] {
        let agents = agent.map { [$0] } ?? Agent.allCases.filter(isPresent)
        guard !agents.isEmpty else {
            throw OperationError(
                code: .agentNotFound,
                message: "No supported agent was found. Choose one with --agent.",
                candidates: Agent.allCases.map { Candidate(agent: $0.rawValue) })
        }
        return try locations(agents).map { location in
            let state = state(at: location.url)
            let result: State =
                switch state {
                case .missing: .installed
                case .outdated: .updated
                case .foreign: .foreign
                default: .unchanged
                }
            if !dryRun && (result == .installed || result == .updated) {
                try FileManager.default.createDirectory(
                    at: location.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(Self.content.utf8).write(to: location.url, options: .atomic)
            }
            return Item(agents: location.agents, path: location.url.path, status: result)
        }
    }

    // Removes only skills that setup installed.
    func remove(agent: Agent?, dryRun: Bool) throws -> [Item] {
        try locations(agent.map { [$0] } ?? Agent.allCases).compactMap { location in
            let state = state(at: location.url)
            switch state {
            case .current, .outdated:
                if !dryRun {
                    try FileManager.default.removeItem(at: location.url)
                    let folder = location.url.deletingLastPathComponent()
                    if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                        try? FileManager.default.removeItem(at: folder)
                    }
                }
                return Item(agents: location.agents, path: location.url.path, status: .removed)
            case .foreign:
                return Item(agents: location.agents, path: location.url.path, status: .foreign)
            default:
                return agent == nil
                    ? nil : Item(agents: location.agents, path: location.url.path, status: .missing)
            }
        }
    }
}

extension SkillInstaller.Agent: Encodable {}

struct SkillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skill",
        abstract: "Install and manage the agent skill that teaches the routing workflow.",
        discussion: """
            setup writes a short SKILL.md for each agent it finds (Claude Code: $CLAUDE_CONFIG_DIR or \
            ~/.claude; Codex, OpenCode, and Pi: ~/.agents, or $CODEX_HOME for Codex). The skill tells the \
            agent to run `switchboard skill show`, so the guide stays current as Switchboard updates. \
            Skills that setup didn't install are left alone.
            """,
        subcommands: [SkillSetup.self, SkillStatus.self, SkillShow.self, SkillRemove.self])
}

struct SkillOptions: ParsableArguments {
    @Option(help: "Only this agent, even if its configuration directory doesn't exist.")
    var agent: SkillInstaller.Agent?

    func installer(_ context: CommandContext) -> SkillInstaller {
        SkillInstaller(home: context.homeDirectory, environment: context.environment)
    }
}

struct SkillReport: Encodable {
    var items: [SkillInstaller.Item]
    var dryRun: Bool
}

private func skillText(_ items: [SkillInstaller.Item], verb: String? = nil) -> String {
    guard !items.isEmpty else {
        return "No supported agents found. Pass --agent claude, codex, opencode, or pi.\n"
    }
    return items.map { item in
        let note = item.status == .foreign ? " (not installed by switchboard; left alone)" : ""
        return
            "\(verb.map { "\($0) " } ?? "")\(item.status.rawValue)\(note): \(item.path)  [\(item.agents.map(\.rawValue).joined(separator: ", "))]\n"
    }.joined()
}

struct SkillSetup: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup", abstract: "Install or update the skill for each agent found. Safe to repeat.")

    @OptionGroup var options: SkillOptions
    @Flag(help: "Show what would change without writing.") var dryRun = false
    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let items: [SkillInstaller.Item]
        do {
            items = try options.installer(context).setup(agent: options.agent, dryRun: dryRun)
        } catch let error as OperationError {
            throw error
        } catch {
            throw OperationError(
                code: .writeFailed, message: "The skill couldn’t be installed. \(error.localizedDescription)")
        }
        return CommandOutput(
            json: SkillReport(items: items, dryRun: dryRun),
            text: skillText(items, verb: dryRun ? "would be" : nil)
                + (dryRun ? "No changes written (dry run).\n" : ""))
    }
}

struct SkillStatus: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Report each skill as current, outdated, missing, or foreign.")

    @OptionGroup var options: SkillOptions
    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let items = options.installer(context).status(agent: options.agent)
        return CommandOutput(json: SkillReport(items: items, dryRun: false), text: skillText(items))
    }
}

struct SkillRemove: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove", abstract: "Remove the skills that setup installed.")

    @OptionGroup var options: SkillOptions
    @Flag(help: "Show what would be removed without removing it.") var dryRun = false
    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let items: [SkillInstaller.Item]
        do {
            items = try options.installer(context).remove(agent: options.agent, dryRun: dryRun)
        } catch {
            throw OperationError(
                code: .writeFailed, message: "The skill couldn’t be removed. \(error.localizedDescription)")
        }
        let text =
            items.isEmpty
            ? "No installed skills found.\n"
            : skillText(items, verb: dryRun ? "would be" : nil)
                + (dryRun ? "No changes written (dry run).\n" : "")
        return CommandOutput(json: SkillReport(items: items, dryRun: dryRun), text: text)
    }
}

struct SkillShow: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show", abstract: "Print the routing guide for agents.")

    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        CommandOutput(json: ["guide": SkillGuide.text], text: SkillGuide.text)
    }
}
