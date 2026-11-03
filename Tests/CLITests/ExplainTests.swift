import Testing

struct ExplainTests {
    @Test func explainNamesTheFirstMatchingRuleAndTheRulesItHides() throws {
        let f = try Fixture()
        try f.rules([
            ["condition": "domain", "value": "example.com", "profile": "Default"],
            ["condition": "domain", "value": "github.com", "profile": "Profile 1"],
            ["condition": "contains", "value": "acme", "profile": "Default"],
        ])
        let out = try f.json(["explain", "https://github.com/acme/api"]).ok().json()
        #expect(out["matchedRule"]["index"] == 2)
        #expect(out["destination"]["profile"] == "Profile 1")
        #expect(out["destination"]["profileName"] == "Work")
        #expect(out["destination"]["browserName"] == "Helium")
        #expect(out["profileStatus"] == "ok")
        #expect(out["alsoMatches"][0]["index"] == 3)

        let text = try f.run(["explain", "https://github.com/acme/api"]).ok().stdout
        #expect(text.contains("Rule 2 matched: domain github.com"), "\(text)")
        #expect(text.contains("Helium · Work (Profile 1)"), "\(text)")
    }

    @Test func anUnmatchedLinkUsesTheDefaultDestination() throws {
        let f = try Fixture()
        try f.rules([])
        let out = try f.json(["explain", "https://example.com"]).ok().json()
        #expect(out.has("matchedRule"))
        #expect(out["matchedRule"] == nil)
        #expect(out["destination"]["profileName"] == "Ryan")
    }

    @Test func aRuleWhoseProfileIsGoneReportsItAsMissing() throws {
        let f = try Fixture()
        try f.rules([["condition": "domain", "value": "a.com", "profile": "Profile 9"]])
        #expect(try f.json(["explain", "https://a.com"]).ok().json()["profileStatus"] == "missing")
    }

    @Test func aChromeRuleWithAHeliumDefaultResolvesItsProfileInChrome() throws {
        let f = try Fixture()
        try f.rules([
            ["condition": "domain", "value": "work.com", "profile": "Default", "browser": .string(f.chrome)],
            ["condition": "domain", "value": "home.com", "profile": "Default"],
        ])
        let work = try f.json(["explain", "https://work.com"]).ok().json()
        #expect(work["destination"]["profileName"] == "Chrome Ryan")
        let home = try f.json(["explain", "https://home.com"]).ok().json()
        #expect(home["destination"]["profileName"] == "Ryan", "a rule without a browser inherits Helium")
    }

    @Test func aLinkThatIsNotACompleteURLIsAUsageError() throws {
        let f = try Fixture()
        let run = try f.json(["explain", "github.com"])
        #expect(run.status == 2)
        #expect(try run.code() == "invalid_argument")
    }

    @Test func explainNeedsExactlyOneLink() throws {
        let f = try Fixture()
        #expect(try f.json(["explain"]).status == 2)
        #expect(try f.json(["explain", "https://a.com", "--last"]).status == 2)
    }
}
