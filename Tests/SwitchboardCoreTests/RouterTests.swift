import Testing

@testable import SwitchboardCore

struct RouterTests {
    func config(_ rules: [Rule]) -> Config { Config(browser: "/Applications/Helium.app", rules: rules) }

    @Test func theFirstMatchingRuleWins() {
        let c = config([Rule(.contains, "acme", profile: "A"), Rule(.domain, "github.com", profile: "B")])
        let d = Router.decide(c, link: "https://github.com/acme/api")
        #expect(d.rule == 0)
        #expect(d.destination.profile == "A")
    }

    @Test func unmatchedLinksUseTheDefaultDestination() {
        let c = config([Rule(.domain, "github.com", profile: "B")])
        #expect(
            Router.decide(c, link: "https://example.com")
                == Decision(destination: c.defaultDestination, rule: nil))
    }

    @Test func domainRulesMatchTheHostAndSubdomainsAtADot() {
        let rule = Rule(.domain, "GitHub.com", profile: "P")
        #expect(Router.matches(rule, link: "https://github.com/x"))
        #expect(Router.matches(rule, link: "https://docs.GITHUB.com"))
        #expect(!Router.matches(rule, link: "https://notgithub.com"))
        #expect(!Router.matches(rule, link: "https://example.com/github.com"))
        #expect(!Router.matches(rule, link: "ftp://github.com"))
    }

    @Test func containsAndExactCompareTheWholeLinkIgnoringCase() {
        #expect(Router.matches(Rule(.contains, "ACME", profile: "P"), link: "https://x.com/?q=acme"))
        #expect(Router.matches(Rule(.exact, "https://x.com/A", profile: "P"), link: "HTTPS://X.COM/a"))
        #expect(!Router.matches(Rule(.exact, "https://x.com", profile: "P"), link: "https://x.com/"))
    }

    @Test func matchingComparesBytesNotCanonicallyEquivalentText() {
        // "é" as one scalar and as "e" plus a combining accent are equal as Swift Strings.
        #expect(
            !Router.matches(Rule(.contains, "caf\u{E9}", profile: "P"), link: "https://x.com/cafe\u{301}"))
        #expect(Router.matches(Rule(.contains, "caf\u{E9}", profile: "P"), link: "https://x.com/CAF\u{C9}"))
    }

    @Test func emptyPatternsNeverMatch() {
        for condition in Condition.allCases {
            #expect(!Router.matches(Rule(condition, "", profile: "P"), link: "https://x.com"))
        }
    }

    @Test func aRuleWithoutABrowserInheritsTheDefaultBrowser() {
        let c = config([
            Rule(.domain, "a.com", profile: "Default"),
            Rule(.domain, "b.com", profile: "Profile 2", browser: "/Applications/Google Chrome.app"),
        ])
        #expect(Router.decide(c, link: "https://a.com").destination.browser == "/Applications/Helium.app")
        #expect(
            Router.decide(c, link: "https://b.com").destination.browser == "/Applications/Google Chrome.app")
    }
}

struct ShadowingTests {
    func rule(_ condition: Condition, _ value: String) -> Rule { Rule(condition, value, profile: "P") }

    @Test func aParentDomainHidesItsSubdomainsButNotTheReverse() {
        #expect(Shadowing.covers(rule(.domain, "github.com"), rule(.domain, "docs.github.com")))
        #expect(!Shadowing.covers(rule(.domain, "docs.github.com"), rule(.domain, "github.com")))
        #expect(!Shadowing.covers(rule(.domain, "hub.com"), rule(.domain, "github.com")))
    }

    @Test func aContainsRuleHidesRulesWhoseTextIncludesIt() {
        #expect(Shadowing.covers(rule(.contains, "acme"), rule(.contains, "acme/api")))
        #expect(Shadowing.covers(rule(.contains, "github"), rule(.domain, "github.com")))
        #expect(!Shadowing.covers(rule(.domain, "github.com"), rule(.contains, "github.com")))
    }

    @Test func anExactRuleIsHiddenWhenAnEarlierRuleMatchesItsLink() {
        #expect(Shadowing.covers(rule(.domain, "x.com"), rule(.exact, "https://x.com/a")))
        #expect(!Shadowing.covers(rule(.domain, "y.com"), rule(.exact, "https://x.com/a")))
    }

    @Test func onlyNewlyHiddenRulesAreReported() {
        let a = rule(.domain, "docs.github.com")
        let b = rule(.domain, "github.com")
        let before = [b, a]
        #expect(Shadowing.unreachable(before) == [Unreachable(rule: 1, by: 0)])
        #expect(Shadowing.newlyUnreachable(before: before, after: before).isEmpty)
        let after = [a, b, rule(.domain, "api.github.com")]
        #expect(Shadowing.newlyUnreachable(before: [b], after: after) == [Unreachable(rule: 2, by: 1)])
    }

    @Test func aHiddenSubdomainRuleIsFixedByMovingItAboveTheRuleThatHidesIt() {
        let rules = [rule(.domain, "github.com"), rule(.contains, "acme"), rule(.domain, "docs.github.com")]
        let hidden = Shadowing.unreachable(rules)
        #expect(hidden == [Unreachable(rule: 2, by: 0)])
        #expect(Shadowing.fix(rules, hidden[0]) == 0)
    }

    @Test func rulesThatCoverEachOtherHaveNoMoveThatFixesThem() {
        let rules = [rule(.contains, "acme"), rule(.contains, "ACME")]
        #expect(Shadowing.fix(rules, Unreachable(rule: 1, by: 0)) == nil)
    }

    @Test func aMoveThatWouldStillLeaveTheRuleHiddenIsNotOffered() {
        // Rule 3 is hidden by rule 1 and rule 2; moving it above rule 2 alone wouldn't help, but
        // the first rule that hides it is rule 1, so the move goes above that.
        let rules = [rule(.contains, "git"), rule(.domain, "github.com"), rule(.domain, "docs.github.com")]
        #expect(Shadowing.fix(rules, Unreachable(rule: 2, by: 1)) == nil)
        #expect(Shadowing.fix(rules, Unreachable(rule: 2, by: 0)) == 0)
    }
}

struct LinkTests {
    @Test func theHostDropsUserInfoPortAndBracketsButKeepsItsCase() {
        #expect(Link("https://me:pw@Example.COM:8443/a?b#c")?.host == "Example.COM")
        #expect(Link("http://[::1]:80/x")?.host == "::1")
        #expect(Link("https://example.com./")?.host == "example.com.")
    }

    @Test func webLinksNeedAnHTTPSchemeAndAHost() {
        #expect(Link.isWeb("HTTPS://github.com"))
        #expect(!Link.isWeb("https:///path"))
        #expect(!Link.isWeb("mailto:me@example.com"))
        #expect(!Link.isWeb("github.com"))
        #expect(!Link.isWeb("https://exa mple.com"))
        #expect(!Link.isWeb("https://example.com:http/"))
    }

    @Test func localFilesNeedAnAbsolutePathOnThisMachine() {
        #expect(Link.isLocalFile("file:///tmp/a.html"))
        #expect(Link.isLocalFile("file://localhost/tmp/a.html"))
        #expect(!Link.isLocalFile("file://server/share/a.html"))
    }

    @Test func thePathStopsAtTheQueryAndFragment() {
        #expect(Link("https://a.com/p/q?x=1#f")?.path == "/p/q")
    }

    @Test func aCombiningMarkAfterADelimiterDoesNotMoveIt() {
        let link = Link("https://a.com/\u{301}x?y")
        #expect(link?.host == "a.com")
        #expect(link?.path == "/\u{301}x")
    }
}

struct TimestampTests {
    @Test func timestampsRoundTripThroughRFC3339() {
        for t: Int64 in [0, 951_782_400, 1_761_757_451, 4_102_444_799] {
            let text = Timestamp(t).rfc3339
            #expect(Timestamp(rfc3339: text) == Timestamp(t), "\(text)")
        }
        #expect(Timestamp(1_761_757_451).rfc3339 == "2025-10-29T17:04:11Z")
    }

    @Test func offsetsAndFractionsAreUnderstood() {
        #expect(
            Timestamp(rfc3339: "2025-10-29T19:04:11.250+02:00") == Timestamp(rfc3339: "2025-10-29T17:04:11Z"))
        #expect(Timestamp(rfc3339: "yesterday") == nil)
        #expect(Timestamp(100).ago(Timestamp(100 + 3 * 3600)) == "3h ago")
    }
}
