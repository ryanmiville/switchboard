import Foundation
import SwitchboardCore

// The agent skill: a short SKILL.md that points agents at `switchboard skill show`, so
// upgrading Switchboard updates the guide they follow.

enum Agent: String, CaseIterable, Encodable {
    case claude, codex, opencode, pi
}

enum SkillState: String, Encodable {
    case current, outdated, missing
    /// A skill with this name that setup didn't install. Left alone.
    case foreign
    case installed, updated, unchanged, removed
}

struct SkillItem: Encodable {
    var agents: [Agent]
    var path: String
    var status: SkillState
}

struct SkillInstaller {
    let home: Home
    let env: Env

    static let markerPrefix = "<!-- \(Identity.cliName)-skill"
    static let marker =
        "\(markerPrefix): installed by `\(Identity.cliName) skill setup`; `\(Identity.cliName) skill remove` deletes it. -->"

    /// The installed SKILL.md.
    static let content = """
        ---
        name: \(Identity.cliName)
        description: Fix which browser and profile links open in, with the \(Identity.cliName) CLI. Use when the user says a link opened in the wrong browser or profile, or asks to send a site to a particular browser profile.
        ---
        \(marker)

        # Switchboard

        Before changing how links are routed, run `\(Identity.cliName) skill show` and follow that guide. It ships with the installed Switchboard, so it always matches this version of the CLI.

        Never edit Switchboard's config.json by hand; use the CLI.

        """

    private func directory(_ variable: String, _ fallback: String) -> URL {
        env[variable].map { URL(fileURLWithPath: $0) } ?? home.appending(fallback)
    }

    /// Agents are found by their configuration folders.
    private func isPresent(_ agent: Agent) -> Bool {
        let folder: URL =
            switch agent {
            case .claude: directory("CLAUDE_CONFIG_DIR", ".claude")
            case .codex: directory("CODEX_HOME", ".codex")
            case .opencode: directory("XDG_CONFIG_HOME", ".config").appendingPathComponent("opencode")
            case .pi: home.appending(".pi")
            }
        return FileManager.default.fileExists(atPath: folder.path)
    }

    private func skillPath(_ agent: Agent) -> URL {
        let root: URL =
            switch agent {
            case .claude: directory("CLAUDE_CONFIG_DIR", ".claude")
            case .codex where env["CODEX_HOME"] != nil: directory("CODEX_HOME", ".codex")
            case .codex, .opencode, .pi: home.appending(".agents")
            }
        return root.appendingPathComponent("skills/\(Identity.cliName)/SKILL.md")
    }

    /// Agents that share a location appear once.
    private func locations(_ agents: [Agent]) -> [(agents: [Agent], path: URL)] {
        var out: [(agents: [Agent], path: URL)] = []
        for agent in agents {
            let path = skillPath(agent)
            if let index = out.firstIndex(where: { $0.path == path }) {
                out[index].agents.append(agent)
            } else {
                out.append(([agent], path))
            }
        }
        return out
    }

    private static func state(_ path: URL) -> SkillState {
        guard let data = try? Files.contents(of: path) else { return .missing }
        let text = String(decoding: data, as: UTF8.self)
        if !text.contains(markerPrefix) { return .foreign }
        return text == content ? .current : .outdated
    }

    /// Detected agents, plus any location that already holds a skill.
    func status(_ agent: Agent?) -> [SkillItem] {
        let agents = agent.map { [$0] } ?? Agent.allCases
        return locations(agents).compactMap { list, path in
            let present = agent != nil ? list : list.filter(isPresent)
            let state = Self.state(path)
            guard !present.isEmpty || state != .missing else { return nil }
            return SkillItem(agents: present.isEmpty ? list : present, path: path.path, status: state)
        }
    }

    func setup(_ agent: Agent?, dryRun: Bool) throws(OperationError) -> [SkillItem] {
        let agents = agent.map { [$0] } ?? Agent.allCases.filter(isPresent)
        if agents.isEmpty {
            throw OperationError(
                .agentNotFound, "No supported agent was found. Choose one with --agent.",
                candidates: Agent.allCases.map { Candidate(agent: $0.rawValue) })
        }
        var items: [SkillItem] = []
        for (list, path) in locations(agents) {
            let result: SkillState =
                switch Self.state(path) {
                case .missing: .installed
                case .outdated: .updated
                case .foreign: .foreign
                default: .unchanged
                }
            if !dryRun && (result == .installed || result == .updated) {
                do {
                    try FileManager.default.createDirectory(
                        at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(Self.content.utf8).write(to: path)
                } catch {
                    throw writeFailed(
                        "The skill couldn’t be written.", "\(path.path): \(error.localizedDescription)")
                }
            }
            items.append(SkillItem(agents: list, path: path.path, status: result))
        }
        return items
    }

    /// Removes only skills that setup installed.
    func remove(_ agent: Agent?, dryRun: Bool) throws(OperationError) -> [SkillItem] {
        let agents = agent.map { [$0] } ?? Agent.allCases
        var items: [SkillItem] = []
        for (list, path) in locations(agents) {
            switch Self.state(path) {
            case .current, .outdated:
                if !dryRun {
                    do {
                        try FileManager.default.removeItem(at: path)
                    } catch {
                        throw writeFailed(
                            "The skill couldn’t be removed.", "\(path.path): \(error.localizedDescription)")
                    }
                    // Only an empty folder goes; anything else in it stays.
                    let folder = path.deletingLastPathComponent()
                    if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                        try? FileManager.default.removeItem(at: folder)
                    }
                }
                items.append(SkillItem(agents: list, path: path.path, status: .removed))
            case .foreign: items.append(SkillItem(agents: list, path: path.path, status: .foreign))
            default:
                if agent != nil { items.append(SkillItem(agents: list, path: path.path, status: .missing)) }
            }
        }
        return items
    }
}

private func skillOutput(_ items: [SkillItem], dryRun: Bool?) -> Output {
    var text = items.isEmpty ? "No skills found.\n" : ""
    for item in items {
        text +=
            "\(Format.padded(item.status.rawValue, 10)) \(item.path)  (\(item.agents.map(\.rawValue).joined(separator: ", ")))\n"
    }
    if dryRun == true { text += "No changes written (dry run).\n" }
    var report = JSONObject()
    report.set("items", items)
    report.setIfPresent("dryRun", dryRun)
    return Output(json: report, text: text)
}

extension SkillShow: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        var report = JSONObject()
        report.set("guide", Guide.text)
        return Output(json: report, text: Guide.text)
    }
}

extension SkillStatus: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        skillOutput(
            SkillInstaller(home: session.context.home, env: session.context.env).status(agent), dryRun: nil)
    }
}

extension SkillSetup: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let installer = SkillInstaller(home: session.context.home, env: session.context.env)
        return skillOutput(try installer.setup(agent, dryRun: dryRun), dryRun: dryRun)
    }
}

extension SkillRemove: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let installer = SkillInstaller(home: session.context.home, env: session.context.env)
        return skillOutput(try installer.remove(agent, dryRun: dryRun), dryRun: dryRun)
    }
}
