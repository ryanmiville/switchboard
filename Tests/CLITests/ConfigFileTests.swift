import Foundation
import Testing

struct ConfigFileTests {
    @Test func usageErrorsExit2AndWithJSONPrintAnErrorObject() throws {
        let f = try Fixture()
        let run = try f.json(["route", "https://a.com"])
        #expect(run.status == 2)
        #expect(try run.code() == "invalid_argument")
        #expect(try run.json()["error"]["message"].string?.contains("--profile") == true)
        let plain = try f.run(["nonsense"])
        #expect(plain.status == 2)
        #expect(plain.stderr.contains("nonsense"))
    }

    @Test func globalOptionsWorkBeforeTheSubcommand() throws {
        let f = try Fixture()
        try f.rules([])
        let out = try f.run(["--json", "rules", "list"]).ok().json()
        #expect(out["rules"] == [])
    }

    @Test func configPrintsTheWholeFileWithItsRevision() throws {
        let f = try Fixture()
        try f.rules([["condition": "domain", "value": "a.com", "profile": "Default"]])
        let out = try f.json(["config"]).ok().json()
        #expect(out["config"]["rules"][0]["value"] == "a.com")
        #expect(out["exists"] == true)
    }

    @Test func aTypoInTheConfigIsReportedWithItsName() throws {
        let f = try Fixture()
        try f.writeConfig(Data(#"{"browser":"b","defaultProfile":"Default","rulez":[]}"#.utf8))
        let out = try f.json(["doctor"]).ok().json()
        #expect(out["ok"] == false)
        #expect(out["config"]["error"].string?.contains("rulez") == true)
    }

    @Test func doctorReportsMissingProfilesAndUnreachableRules() throws {
        let f = try Fixture()
        try f.rules([
            ["condition": "domain", "value": "github.com", "profile": "Default"],
            ["condition": "domain", "value": "docs.github.com", "profile": "Nobody"],
        ])
        let out = try f.json(["doctor"]).ok().json()
        #expect(out["ok"] == false)
        #expect(out["rules"].array.map { $0["problem"] } == ["profile_missing", "unreachable"])
        #expect(out["browsers"][0]["profileCount"] == 2)

        let g = try Fixture()
        try g.rules([])
        #expect(try g.json(["doctor"]).ok().json()["ok"] == true)
    }

    @Test func profilesListsEachBrowserWithItsDirectoriesAndNames() throws {
        let f = try Fixture()
        try f.rules([])
        let out = try f.json(["profiles"]).ok().json()
        #expect(out["browsers"].array.map { $0["name"] } == ["Google Chrome", "Helium"])
        #expect(out["browsers"][1]["isDefault"] == true)
        #expect(out["browsers"][1]["profiles"][1] == ["profile": "Profile 1", "profileName": "Work"])
        let one = try f.json(["profiles", "--browser", "chrome"]).ok().json()
        #expect(one["browsers"].array.count == 1)
        let none = try f.json(["profiles", "--browser", "Firefox"])
        #expect(none.status == 3)
        #expect(try none.code() == "browser_not_found")
    }
}

struct SkillTests {
    @Test func skillSetupInstallsForDetectedAgentsAndLeavesForeignSkillsAlone() throws {
        let f = try Fixture()
        let manager = FileManager.default
        try manager.createDirectory(at: f.home.appending(".claude"), withIntermediateDirectories: true)
        try manager.createDirectory(at: f.home.appending(".codex"), withIntermediateDirectories: true)
        let foreign = f.home.appending(".agents/skills/switchboard-next/SKILL.md")
        try manager.createDirectory(
            at: foreign.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: foreign)

        let out = try f.json(["skill", "setup"]).ok().json()
        #expect(out["items"].array.map { $0["status"] } == ["installed", "foreign"])
        #expect(manager.fileExists(atPath: f.home.appending(".claude/skills/switchboard-next/SKILL.md").path))
        #expect(try String(contentsOf: foreign, encoding: .utf8) == "mine")

        #expect(try f.json(["skill", "setup"]).ok().json()["items"][0]["status"] == "unchanged")
        #expect(try f.json(["skill", "status"]).ok().json()["items"][0]["status"] == "current")
        #expect(try f.json(["skill", "remove"]).ok().json()["items"][0]["status"] == "removed")
        #expect(!manager.fileExists(atPath: f.home.appending(".claude/skills/switchboard-next").path))
        #expect(try String(contentsOf: foreign, encoding: .utf8) == "mine")
    }

    @Test func skillSetupWithNoAgentFoundExits3() throws {
        let f = try Fixture()
        let run = try f.json(["skill", "setup"])
        #expect(run.status == 3)
        #expect(try run.code() == "agent_not_found")
    }

    @Test func skillShowPrintsTheGuideForThisCLI() throws {
        let f = try Fixture()
        let text = try f.run(["skill", "show"]).ok().stdout
        #expect(text.hasPrefix("# Switchboard routing guide"))
        #expect(text.contains("switchboard-next explain --last"))
        #expect(!text.contains("switchboard-rs"))
    }
}
