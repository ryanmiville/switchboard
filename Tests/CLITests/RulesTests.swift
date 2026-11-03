import Foundation
import SwitchboardCore
import Testing

struct RulesTests {
    @Test func rulesListShowsInheritanceProblemsAndHiddenRules() throws {
        let f = try Fixture()
        try f.rules([
            ["condition": "domain", "value": "github.com", "profile": "Default"],
            [
                "condition": "domain", "value": "docs.github.com", "profile": "Profile 2",
                "browser": .string(f.chrome),
            ],
            ["condition": "contains", "value": "x", "profile": "Nobody"],
        ])
        let out = try f.json(["rules", "list"]).ok().json()
        let rules = out["rules"]
        #expect(rules[0].has("browser"))
        #expect(rules[0]["browser"] == nil)
        #expect(rules[0]["destination"]["browserName"] == "Helium")
        #expect(rules[1]["shadowedBy"] == 1)
        #expect(rules[1]["destination"]["profileName"] == "Work")
        #expect(rules[2]["profileStatus"] == "missing")
        #expect(out["default"]["destination"]["profileName"] == "Ryan")
        #expect(out["revision"].string?.count == 64)

        let text = try f.run(["rules", "list"]).ok().stdout
        #expect(text.contains("(default browser)"), "\(text)")
        #expect(text.contains("Never matches: rule 1"), "\(text)")
    }

    @Test func changingARulesBrowserRequiresAProfile() throws {
        let f = try Fixture()
        try f.rules([["condition": "domain", "value": "a.com", "profile": "Default"]])
        #expect(try f.json(["rules", "update", "1", "--browser", "Chrome"]).status == 2)
        let out = try f.json(["rules", "update", "1", "--browser", "Chrome", "--profile", "Profile 3"]).ok()
            .json()
        #expect(out["rule"]["destination"]["browserName"] == "Google Chrome")
        #expect(out["previous"]["destination"]["browserName"] == "Helium")
    }

    @Test func movingAndRemovingReportRecentLinksThatWouldOpenElsewhere() throws {
        let f = try Fixture()
        try f.rules([
            ["condition": "domain", "value": "a.com", "profile": "Profile 1"],
            ["condition": "contains", "value": "a.com/x", "profile": "Default"],
        ])
        try f.history([entry("aaaa0001", "https://a.com/x?token=secret")])
        let out = try f.json(["rules", "remove", "1", "--dry-run"]).ok().json()
        #expect(out["historyChecked"] == true)
        #expect(out["historyChanges"][0]["url"] == "https://a.com/x?…", "history URLs are redacted")
        #expect(out["historyChanges"][0]["after"]["rule"]["index"] == 1)

        let moved = try f.json(["rules", "move", "2", "1"]).ok().json()
        #expect(moved["action"] == "moved")
        #expect(moved["from"] == 2)
        #expect(try f.readConfig()["rules"][0]["value"] == "a.com/x")
    }

    @Test func aMissingRuleExits3WithTheRulesListed() throws {
        let f = try Fixture()
        try f.rules([["condition": "domain", "value": "a.com", "profile": "Default"]])
        let run = try f.json(["rules", "remove", "4"])
        #expect(run.status == 3)
        #expect(try run.code() == "rule_not_found")
        #expect(try run.json()["error"]["candidates"][0]["value"] == "a.com")
        #expect(try f.run(["rules", "remove", "4"]).stderr.contains("rule 1: domain a.com"))
    }

    @Test func theDefaultBrowserCantChangeWhileRulesInheritIt() throws {
        let f = try Fixture()
        try f.rules([["condition": "domain", "value": "a.com", "profile": "Profile 1"]])
        let run = try f.json(["default", "--browser", "Chrome", "--profile", "Default"])
        #expect(run.status == 3)
        #expect(try run.code() == "inheriting_rules")
        let suggestion = try run.json()["error"]["candidates"][0]["suggestion"].string ?? ""
        #expect(
            suggestion.contains("rules update 1 --browser") && suggestion.contains("--profile 'Profile 1'"))

        let g = try Fixture()
        try g.rules([])
        let out = try g.json(["default", "--browser", "Chrome", "--profile", "Chrome Ryan"]).ok().json()
        #expect(out["destination"]["browserName"] == "Google Chrome")
        #expect(try g.readConfig()["defaultProfile"] == "Default")
    }

    @Test func aMalformedConfigExits4AndIsNeverReplaced() throws {
        let f = try Fixture()
        try f.writeConfig(Data("{\"browser\": ".utf8))
        let run = try f.json(["route", "https://a.com", "--profile", "Work"])
        #expect(run.status == 4)
        #expect(try run.code() == "config_invalid")
        #expect(f.configBytes() == Data("{\"browser\": ".utf8))
    }

    @Test func withNoConfigTheCLISaysNoDefaultBrowserIsChosen() throws {
        let f = try Fixture()
        let text = try f.run(["rules", "list"]).ok().stdout
        #expect(text.contains("No default browser is chosen"), "\(text)")
        let out = try f.json(["default", "--browser", "Helium", "--profile", "Work"]).ok().json()
        #expect(out["destination"]["profile"] == "Profile 1")
        #expect(try f.readConfig()["browser"] == .string(f.helium))
    }
}

// Launching through real browser discovery and a real process. The fixture browser's program
// records its arguments.
struct LaunchTests {
    @Test func aLaunchPassesTheProfileDirectoryAndTheLinkExactlyAsReceived() throws {
        let f = try Fixture()
        let link = "https://EXAMPLE.com/Path/%7Euser?q=a%20b#frag"
        try Launch.launch(
            link, at: Destination(browser: f.chrome, profile: "Profile 3"), browsers: f.temporary.browsers)
        #expect(f.temporary.waitForLaunches(1) == [["--profile-directory=Profile 3", link]])
    }

    @Test func aLegacyDisplayNameLaunchesItsDirectoryInItsOwnBrowser() throws {
        let f = try Fixture()
        try Launch.launch(
            "https://a.com", at: Destination(browser: f.helium, profile: "Work"),
            browsers: f.temporary.browsers)
        #expect(f.temporary.waitForLaunches(1).first?.first == "--profile-directory=Profile 1")
    }

    @Test func launchingRefusesBadLinksAndUnknownProfilesWithoutStartingAnything() throws {
        let f = try Fixture()
        let browsers = f.temporary.browsers
        #expect(throws: LaunchError.invalidURL) {
            try Launch.launch(
                "javascript:alert(1)", at: Destination(browser: f.chrome, profile: "Default"),
                browsers: browsers)
        }
        #expect(throws: LaunchError.profile(.ambiguous("Work"))) {
            try Launch.launch(
                "https://a.com", at: Destination(browser: f.chrome, profile: "Work"), browsers: browsers)
        }
        let gone = Destination(browser: f.home.appending("Nope.app").path, profile: "Default")
        #expect(throws: LaunchError.self) { try Launch.launch("https://a.com", at: gone, browsers: browsers) }
        Thread.sleep(forTimeInterval: 0.05)
        #expect(f.temporary.recordedLaunches().isEmpty)
    }
}
