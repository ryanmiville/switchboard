import Foundation
import Testing

struct RouteTests {
    @Test func routeAppendsADomainRuleWhenOnlyTheDefaultMatched() throws {
        let f = try Fixture()
        try f.rules([])
        let out = try f.json(["route", "https://docs.github.com/x", "--profile", "Work"]).ok().json()
        #expect(out["action"] == "added")
        #expect(out["written"] == true)
        #expect(out["after"]["destination"]["profile"] == "Profile 1")
        #expect(
            try f.readConfig()["rules"][0] == [
                "condition": "domain", "value": "docs.github.com", "profile": "Profile 1",
            ])
    }

    @Test func routeInsertsJustBeforeTheRuleThatMatchesNow() throws {
        let f = try Fixture()
        try f.rules([
            ["condition": "domain", "value": "a.com", "profile": "Default"],
            ["condition": "contains", "value": "github", "profile": "Default"],
        ])
        let out = try f.json([
            "route", "https://github.com/acme", "--profile", "Profile 1", "--match", "contains", "--value",
            "github.com/acme",
        ]).ok().json()
        #expect(out["rule"]["index"] == 2)
        let rules = try f.readConfig()["rules"]
        #expect(rules[1]["value"] == "github.com/acme")
        #expect(rules[2]["value"] == "github")
    }

    @Test func routeUpdatesARuleWithTheSameConditionAndPatternInPlace() throws {
        let f = try Fixture()
        try f.rules([["condition": "domain", "value": "GitHub.com", "profile": "Default"]])
        let out = try f.json(["route", "https://github.com", "--profile", "Profile 3", "--browser", "Chrome"])
            .ok().json()
        #expect(out["action"] == "updated")
        let config = try f.readConfig()
        #expect(config["rules"].array.count == 1)
        #expect(config["rules"][0]["browser"] == .string(f.chrome))
        #expect(config["rules"][0]["profile"] == "Profile 3")
    }

    @Test func anAmbiguousProfileNameExits3WithCandidatesAndWritesNothing() throws {
        let f = try Fixture()
        try f.rules([])
        let before = f.configBytes()
        let run = try f.json(["route", "https://x.com", "--browser", "Google Chrome", "--profile", "Work"])
        #expect(run.status == 3)
        #expect(try run.code() == "ambiguous_profile")
        #expect(
            try run.json()["error"]["candidates"].array.map { $0["profile"] } == ["Profile 2", "Profile 3"])
        #expect(f.configBytes() == before)
    }

    @Test func aDirectoryIdentifierWinsOverACollidingDisplayName() throws {
        let f = try Fixture()
        try f.rules([])
        let out = try f.json(["route", "https://x.com", "--browser", "Chrome", "--profile", "Profile 2"]).ok()
            .json()
        #expect(out["after"]["destination"]["profileName"] == "Work")
    }

    @Test func theSameDirectoryInTwoBrowsersIsResolvedInTheBrowserAskedFor() throws {
        let f = try Fixture()
        try f.rules([])
        let out = try f.json(["route", "https://x.com", "--browser", "Chrome", "--profile", "Default"]).ok()
            .json()
        #expect(out["after"]["destination"]["profileName"] == "Chrome Ryan")
        #expect(out["after"]["destination"]["browserName"] == "Google Chrome")
    }

    @Test func routeIsANoOpWhenTheLinkAlreadyOpensThere() throws {
        let f = try Fixture()
        try f.rules([])
        let before = f.configBytes()
        let out = try f.json(["route", "https://x.com", "--profile", "Ryan"]).ok().json()
        #expect(out["changed"] == false)
        #expect(out["rule"] == nil)
        #expect(f.configBytes() == before)
    }

    @Test func routeRefusesToHideALaterRuleUnlessAllowed() throws {
        let f = try Fixture()
        try f.rules([
            ["condition": "contains", "value": "acme", "profile": "Default"],
            ["condition": "domain", "value": "docs.github.com", "profile": "Default"],
        ])
        let before = f.configBytes()
        let args = [
            "route", "https://github.com/acme", "--profile", "Work", "--match", "contains", "--value",
            "github",
        ]
        let run = try f.json(args)
        #expect(run.status == 1, "\(run.stdout)")
        #expect(try run.code() == "would_shadow")
        #expect(try run.json()["error"]["candidates"][0]["index"] == 3)
        #expect(f.configBytes() == before)

        let out = try f.json(args + ["--allow-shadowing"]).ok().json()
        #expect(out["shadowedRules"][0]["value"] == "docs.github.com")
    }

    @Test func anExactRuleForALinkAnEarlierDomainRuleMatchesStillWorks() throws {
        let f = try Fixture()
        try f.rules([["condition": "domain", "value": "github.com", "profile": "Default"]])
        let run = try f.json(["route", "https://github.com", "--profile", "Work", "--match", "exact"])
        #expect(run.status == 0, "\(run.stdout)")
    }

    @Test func aDryRunReportsTheChangeAndWritesNothing() throws {
        let f = try Fixture()
        try f.rules([])
        let before = f.configBytes()
        let out = try f.json(["route", "https://x.com", "--profile", "Work", "--dry-run"]).ok().json()
        #expect(out["changed"] == true)
        #expect(out["written"] == false)
        #expect(f.configBytes() == before)
    }

    @Test func aStaleRevisionExits5AndLeavesTheFileAlone() throws {
        let f = try Fixture()
        try f.rules([])
        let revision = try #require(try f.json(["rules", "list"]).ok().json()["revision"].string)
        _ = try f.json(["route", "https://a.com", "--profile", "Work"]).ok()
        let afterFirst = f.configBytes()
        let run = try f.json(["route", "https://b.com", "--profile", "Work", "--if-revision", revision])
        #expect(run.status == 5)
        #expect(try run.code() == "conflict")
        #expect(f.configBytes() == afterFirst)
    }

    @Test func routeLeavesUnrelatedLegacyRulesExactlyAsTheyWere() throws {
        let f = try Fixture()
        // A current-app file: `routes`, a display-name profile, no browser on the rule.
        try f.writeConfig(
            Data(
                #"{"browser":"\#(f.helium)","defaultProfile":"Ryan","routes":[{"condition":"domain","value":"old.com","profile":"Work"}]}"#
                    .utf8))
        _ = try f.json(["route", "https://new.com", "--profile", "Profile 1"]).ok()
        let config = try f.readConfig()
        #expect(config["defaultProfile"] == "Ryan", "the default isn't normalized")
        #expect(config["rules"][0] == ["condition": "domain", "value": "old.com", "profile": "Work"])
        #expect(config["rules"][1]["value"] == "new.com")
    }
}
