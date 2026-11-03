import Foundation
import SwitchboardFixtures
import Testing

@testable import SwitchboardCore

// Rule edits against fixture browsers: a Helium default, a Chrome rule, and the same profile
// directory meaning different people in the two browsers.
struct RuleOperationsTests {
    struct Setup {
        let fixture: TemporaryHome
        let helium: String
        let chrome: String

        init() throws {
            fixture = try TemporaryHome()
            helium = try fixture.installBrowser(
                .helium, name: "Helium", profiles: [("Default", "Ryan"), ("Profile 1", "Side")])
            chrome = try fixture.installBrowser(
                .chrome, name: "Google Chrome", profiles: [("Default", "Work"), ("Profile 2", "Client")])
        }

        func operations(_ rules: [Rule] = []) -> RuleOperations {
            RuleOperations(
                config: Config(browser: helium, defaultProfile: "Default", rules: rules),
                browsers: fixture.browsers,
                home: fixture.home)
        }
    }

    @Test func routingAddsADomainRuleForTheChromeProfileAndVerifiesIt() throws {
        let setup = try Setup()
        defer { setup.fixture.remove() }
        let ops = setup.operations()
        let change = try ops.route(
            RouteRequest(url: "https://gitlab.acme.com/x", profile: "Client", browser: "chrome"))
        #expect(change.action == .added)
        #expect(change.config.rules == [change.config.rules[0]])
        #expect(change.config.rules[0].condition == .domain)
        #expect(change.config.rules[0].value == "gitlab.acme.com")
        #expect(change.config.rules[0].browser == setup.chrome)
        #expect(change.config.rules[0].profile == "Profile 2")
        let decision = ops.with(change.config).decision("https://gitlab.acme.com/y")
        #expect(decision.destination.label == "Google Chrome · Client (Profile 2)")
    }

    @Test func routingToWhereALinkAlreadyGoesChangesNothing() throws {
        let setup = try Setup()
        defer { setup.fixture.remove() }
        let change = try setup.operations().route(RouteRequest(url: "https://x.com", profile: "Ryan"))
        #expect(change.action == .unchanged)
        #expect(!change.changed)
    }

    @Test func aNewRuleGoesJustBeforeTheRuleThatMatchesNow() throws {
        let setup = try Setup()
        defer { setup.fixture.remove() }
        let ops = setup.operations([
            Rule(.contains, "acme", profile: "Profile 1"), Rule(.domain, "z.com", profile: "Default"),
        ])
        let change = try ops.route(RouteRequest(url: "https://docs.acme.com", profile: "Default"))
        #expect(change.index == 0)
        #expect(change.config.rules.map(\.value) == ["docs.acme.com", "acme", "z.com"])
    }

    @Test func aRuleThatWouldHideOthersNeedsPermission() throws {
        let setup = try Setup()
        defer { setup.fixture.remove() }
        let ops = setup.operations([Rule(.domain, "docs.github.com", profile: "Profile 1")])
        // The new rule goes before docs.github.com, which matches the link now, and would hide it.
        let request = RouteRequest(url: "https://docs.github.com/x", profile: "Default", value: "github.com")
        #expect {
            try ops.route(request)
        } throws: { ($0 as? OperationError)?.code == .wouldShadow }
        var allowed = request
        allowed.allowShadowing = true
        let change = try ops.route(allowed)
        #expect(change.config.rules.map(\.value) == ["github.com", "docs.github.com"])
        #expect(change.unreachable == [Unreachable(rule: 1, by: 0)])
    }

    @Test func aProfileNameIsResolvedInTheRulesOwnBrowser() throws {
        let setup = try Setup()
        defer { setup.fixture.remove() }
        // "Work" exists only in Chrome, so a rule inheriting Helium can't use it.
        let ops = setup.operations([Rule(.domain, "a.com", profile: "Default")])
        #expect {
            try ops.updateRule(1, RuleUpdate(profile: "Work"))
        } throws: { error in
            let error = error as? OperationError
            return error?.code == .profileNotFound
                && error?.candidates.map(\.profileName) == ["Ryan", "Side"]
        }
        let moved = try ops.updateRule(1, RuleUpdate(profile: "Work", browser: .browser("Google Chrome")))
        #expect(moved.config.rules[0].browser == setup.chrome)
        #expect(moved.config.rules[0].profile == "Default")
        #expect(throws: OperationError.self) {
            try ops.updateRule(1, RuleUpdate(browser: .browser("chrome")))
        }
    }

    @Test func theDefaultBrowserCantChangeWhileRulesInheritIt() throws {
        let setup = try Setup()
        defer { setup.fixture.remove() }
        let ops = setup.operations([
            Rule(.domain, "a.com", profile: "Profile 1"),
            Rule(.domain, "b.com", profile: "Default", browser: setup.chrome),
        ])
        #expect {
            try ops.setDefault(browser: "chrome", profile: "Work")
        } throws: { error in
            let error = error as? OperationError
            return error?.code == .inheritingRules && error?.code.exitCode == 3
                && error?.candidates.first?.suggestion?.contains("rules update 1 --browser") == true
        }
        let profileOnly = try ops.setDefault(browser: nil, profile: "Side")
        #expect(profileOnly.config.defaultProfile == "Profile 1")
        #expect(profileOnly.changed)
    }

    @Test func legacyRulesWithoutABrowserAndDisplayNamesStillDescribe() throws {
        let setup = try Setup()
        defer { setup.fixture.remove() }
        let ops = setup.operations([
            Rule(.domain, "a.com", profile: "Side"), Rule(.domain, "b.com", profile: "Gone"),
        ])
        let rules = ops.rules()
        #expect(rules[0].destination.profile == "Profile 1")
        #expect(rules[0].profileStatus == .ok)
        #expect(rules[1].profileStatus == .missing)
        let json = String(decoding: JSON.line(rules[1]), as: UTF8.self)
        #expect(json.contains(#""browser":null"#), "unset fields are written as null, as the Rust CLI does")
        #expect(json.contains(#""shadowedBy":null"#))
    }

    @Test func browsersResolveByPathIDOrNameAndAmbiguityIsRefused() throws {
        let setup = try Setup()
        defer { setup.fixture.remove() }
        try setup.fixture.installBrowser(.chromeBeta, name: "Chrome Beta")
        let ops = setup.operations()
        #expect(try ops.resolveBrowser("net.imput.helium").locator == setup.helium)
        #expect(try ops.resolveBrowser("helium.app").locator == setup.helium)
        #expect(try ops.resolveBrowser(setup.chrome).locator == setup.chrome)
        #expect(try ops.resolveBrowser("~/Applications/Helium.app").locator == setup.helium)
        #expect(throws: OperationError.self) { try ops.resolveBrowser("Firefox") }
        let one = try ops.resolveBrowser("chrome")
        #expect(one.locator == setup.chrome, "the short name belongs to Chrome only")
    }

    @Test func movingAndRemovingRulesUseOneBasedPositions() throws {
        let setup = try Setup()
        defer { setup.fixture.remove() }
        let ops = setup.operations([
            Rule(.domain, "a.com", profile: "Default"), Rule(.domain, "b.com", profile: "Default"),
        ])
        #expect(try ops.moveRule(from: 2, to: 1).config.rules.map(\.value) == ["b.com", "a.com"])
        #expect(try ops.removeRule(1).config.rules.map(\.value) == ["b.com"])
        #expect {
            try ops.removeRule(3)
        } throws: { ($0 as? OperationError)?.message == "There is no rule 3. Rules are numbered 1–2." }
    }

    @Test func shellQuotingAndListsReadNaturally() {
        #expect(RuleOperations.quoted("/Applications/Helium.app") == "/Applications/Helium.app")
        #expect(RuleOperations.quoted("Profile 1") == "'Profile 1'")
        #expect(RuleOperations.quoted("it's") == "'it'\\''s'")
        #expect(RuleOperations.list(["a", "b", "c"]) == "a, b, and c")
    }
}
