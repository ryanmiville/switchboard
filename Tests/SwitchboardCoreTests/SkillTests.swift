import Foundation
import Testing

@testable import SwitchboardCore

struct SkillTests {
    private func run(_ fixture: Fixture, _ arguments: [String], environment: [String: String] = [:])
        -> CommandLineTool.Outcome
    {
        CommandLineTool.run(
            arguments + ["--json"],
            context: CommandContext(
                environment: environment, homeDirectory: fixture.root, applicationDirectories: [],
                executableURL: nil))
    }

    private func items(_ outcome: CommandLineTool.Outcome) throws -> [[String: Any]] {
        let report = try #require(
            JSONSerialization.jsonObject(with: Data(outcome.stdout.utf8)) as? [String: Any])
        return try #require(report["items"] as? [[String: Any]])
    }

    private func statuses(_ outcome: CommandLineTool.Outcome) throws -> [String] {
        try items(outcome).compactMap { $0["status"] as? String }
    }

    @Test func setupStatusAndRemoveManageEachAgentsSkill() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        for folder in [".claude", ".codex", ".pi"] {
            try FileManager.default.createDirectory(
                at: fixture.root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let claude = fixture.root.appendingPathComponent(".claude/skills/switchboard/SKILL.md")
        let shared = fixture.root.appendingPathComponent(".agents/skills/switchboard/SKILL.md")
        #expect(try statuses(run(fixture, ["skill", "status"])) == ["missing", "missing"])
        #expect(try statuses(run(fixture, ["skill", "setup", "--dry-run"])) == ["installed", "installed"])
        #expect(!FileManager.default.fileExists(atPath: claude.path))
        let installed = try items(run(fixture, ["skill", "setup"]))
        #expect(installed.compactMap { $0["path"] as? String } == [claude.path, shared.path])
        #expect(installed.last?["agents"] as? [String] == ["codex", "pi"])
        let text = try String(contentsOf: claude, encoding: .utf8)
        #expect(text.hasPrefix("---\nname: switchboard\n"))
        #expect(text.contains("switchboard skill show"))
        #expect(try statuses(run(fixture, ["skill", "setup"])) == ["unchanged", "unchanged"])
        let current = try items(run(fixture, ["skill", "status"]))
        #expect(current.compactMap { $0["status"] as? String } == ["current", "current"])
        #expect(current.last?["agents"] as? [String] == ["codex", "pi"])

        try Data(text.replacingOccurrences(of: "Never edit", with: "Don't edit").utf8).write(to: shared)
        #expect(try statuses(run(fixture, ["skill", "status"])) == ["current", "outdated"])
        #expect(try statuses(run(fixture, ["skill", "setup"])) == ["unchanged", "updated"])
        #expect(try String(contentsOf: shared, encoding: .utf8) == SkillInstaller.content)

        #expect(try statuses(run(fixture, ["skill", "remove", "--agent", "claude"])) == ["removed"])
        #expect(!FileManager.default.fileExists(atPath: claude.deletingLastPathComponent().path))
        #expect(try statuses(run(fixture, ["skill", "remove"])) == ["removed"])
        #expect(!FileManager.default.fileExists(atPath: shared.path))
        #expect(try statuses(run(fixture, ["skill", "remove"])).isEmpty)
    }

    @Test func skillsThatSetupDidNotInstallAreLeftAlone() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let skill = fixture.root.appendingPathComponent(".claude/skills/switchboard/SKILL.md")
        try FileManager.default.createDirectory(
            at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        let foreign = Data("---\nname: switchboard\ndescription: Someone else's.\n---\n".utf8)
        try foreign.write(to: skill)
        #expect(try statuses(run(fixture, ["skill", "status"])) == ["foreign"])
        #expect(try statuses(run(fixture, ["skill", "setup"])) == ["foreign"])
        #expect(try statuses(run(fixture, ["skill", "remove"])) == ["foreign"])
        #expect(try Data(contentsOf: skill) == foreign)
    }

    @Test func agentLocationsFollowTheirEnvironment() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let none = run(fixture, ["skill", "setup"])
        #expect(none.status == 3)
        #expect(none.stdout.contains("agent_not_found"))
        let claudeHome = fixture.root.appendingPathComponent("claude-config")
        let codexHome = fixture.root.appendingPathComponent("codex-home")
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let environment = ["CLAUDE_CONFIG_DIR": claudeHome.path, "CODEX_HOME": codexHome.path]
        let installed = try items(run(fixture, ["skill", "setup"], environment: environment))
        #expect(
            installed.compactMap { $0["path"] as? String } == [
                claudeHome.appendingPathComponent("skills/switchboard/SKILL.md").path,
                codexHome.appendingPathComponent("skills/switchboard/SKILL.md").path,
            ])
        let pi = try items(run(fixture, ["skill", "setup", "--agent", "pi"]))
        #expect(
            pi.first?["path"] as? String
                == fixture.root.appendingPathComponent(".agents/skills/switchboard/SKILL.md").path)
        #expect(run(fixture, ["skill", "setup", "--agent", "cursor"]).status == 64)
    }

    @Test func showPrintsTheCompiledGuide() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let text = CommandLineTool.run(
            ["skill", "show"],
            context: CommandContext(environment: [:], homeDirectory: fixture.root, executableURL: nil))
        #expect(text.status == 0)
        #expect(text.stdout == SkillGuide.text)
        #expect(text.stdout.contains("switchboard explain --last"))
        #expect(text.stdout.contains("Never guess."))
        let report = try #require(
            JSONSerialization.jsonObject(with: Data(run(fixture, ["skill", "show"]).stdout.utf8))
                as? [String: String])
        #expect(report["guide"] == SkillGuide.text)
    }
}
