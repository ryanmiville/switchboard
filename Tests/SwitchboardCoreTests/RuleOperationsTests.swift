import Foundation
import Testing

@testable import SwitchboardCore

struct RuleOperationsTests {
    struct Browsers {
        let chrome: String
        let helium: String
    }

    // Chrome and Helium both have "Default" and "Profile 2" directories that belong to different people.
    private func browsers(_ fixture: Fixture) throws -> Browsers {
        let chrome = try fixture.browser(name: "Google Chrome", bundleName: "Chrome")
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        try fixture.profiles(["Default": "Personal", "Profile 2": "Work"])
        try fixture.profiles(
            ["Default": "Ryan", "Profile 1": "H3", "Profile 2": "Helium Work"], folder: "net.imput.helium")
        return Browsers(chrome: chrome.path, helium: helium.path)
    }

    private func operations(_ fixture: Fixture, _ config: Config) -> RuleOperations {
        RuleOperations(
            config: config,
            catalog: BrowserCatalog(homeDirectory: fixture.root, applicationDirectories: [fixture.root]))
    }

    private func url(_ value: String) throws -> URL { try #require(URL(string: value)) }

    private func code(_ body: () throws -> Void) -> OperationError.Code? {
        do {
            try body()
            return nil
        } catch let error as OperationError {
            return error.code
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }

    @Test func routeAppendsWhenOnlyTheDefaultMatched() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [Route(condition: .domain, value: "youtube.com")])
        let link = try url("https://github.com/acme/api/pull/12")
        let result = try operations(fixture, config).route(
            RouteRequest(url: link, profile: "Work", browser: "Chrome"))
        #expect(result.action == .added)
        #expect(result.index == 1)
        #expect(result.config.routes.map(\.value) == ["youtube.com", "github.com"])
        #expect(result.config.routes[1].browser == paths.chrome)
        #expect(result.config.routes[1].profile == "Profile 2")
        #expect(
            Router(config: result.config).route(url: link)
                == Destination(browser: paths.chrome, profile: "Profile 2"))
    }

    @Test func routeInsertsImmediatelyBeforeTheMatchingRule() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [
                Route(condition: .domain, value: "youtube.com", profile: "Profile 1"),
                Route(condition: .domain, value: "github.com", profile: "Default"),
            ])
        let result = try operations(fixture, config).route(
            RouteRequest(
                url: try url("https://github.com/acme/api"), profile: "Work", browser: "com.google.Chrome",
                condition: .contains, value: "github.com/acme"))
        #expect(result.index == 1)
        #expect(result.config.routes.map(\.value) == ["youtube.com", "github.com/acme", "github.com"])
        #expect(
            Router(config: result.config).route(url: try url("https://github.com/other"))
                == Destination(browser: paths.helium, profile: "Default"))
    }

    @Test func routeUpdatesARuleWithTheSamePatternInPlace() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [Route(condition: .domain, value: "GitHub.com", profile: "Default")])
        let link = try url("https://github.com/acme")
        let toChrome = try operations(fixture, config).route(
            RouteRequest(url: link, profile: "Work", browser: "Chrome"))
        #expect(toChrome.action == .updated)
        #expect(toChrome.config.routes.count == 1)
        #expect(toChrome.config.routes[0].id == config.routes[0].id)
        #expect(toChrome.config.routes[0].browser == paths.chrome)
        #expect(toChrome.config.routes[0].profile == "Profile 2")
        // Without --browser the rule inherits the default browser again, and the profile is Helium's.
        let back = try operations(fixture, toChrome.config).route(RouteRequest(url: link, profile: "h3"))
        #expect(back.config.routes[0].browser == nil)
        #expect(back.config.routes[0].profile == "Profile 1")
    }

    @Test func routeChangesNothingWhenTheURLAlreadyGoesThere() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        // A legacy display-name profile resolves to the same directory.
        let config = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [Route(condition: .domain, value: "github.com", profile: "H3")])
        let result = try operations(fixture, config).route(
            RouteRequest(
                url: try url("https://github.com/a"), profile: "Profile 1", browser: paths.helium + "/"))
        #expect(!result.changed)
        #expect(result.index == 0)
        #expect(result.config == config)
    }

    @Test func shadowingIsRefusedUnlessAllowed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [Route(condition: .domain, value: "docs.github.com", profile: "Profile 1")])
        let request = RouteRequest(
            url: try url("https://docs.github.com/en"), profile: "Work", browser: "Chrome",
            value: "github.com")
        do {
            _ = try operations(fixture, config).route(request)
            Issue.record("A shadowing rule was accepted")
        } catch let error as OperationError {
            #expect(error.code == .wouldShadow)
            #expect(error.code.exitCode == 1)
            #expect(error.candidates.map(\.index) == [2])
        }
        var allowed = request
        allowed.allowShadowing = true
        let result = try operations(fixture, config).route(allowed)
        #expect(result.unreachable == [Shadowing.Unreachable(rule: 1, by: 0)])

        let contains = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [Route(condition: .contains, value: "github.com/acme/api", profile: "Profile 1")])
        #expect(
            code {
                _ = try operations(fixture, contains).route(
                    RouteRequest(
                        url: try url("https://github.com/acme/api"), profile: "Work", browser: "Chrome",
                        condition: .contains, value: "acme"))
            } == .wouldShadow)
    }

    @Test func changesAreVerifiedWithTheRouterBeforeTheyAreAccepted() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let empty = Config(browser: paths.helium, defaultProfile: "Default", routes: [])
        let link = try url("https://github.com/x")
        #expect(
            code {
                _ = try operations(fixture, empty).route(
                    RouteRequest(
                        url: link, profile: "Work", browser: "Chrome", condition: .exact,
                        value: "https://github.com/y"))
            } == .verificationFailed)
        #expect(
            code {
                _ = try operations(fixture, empty).route(
                    RouteRequest(
                        url: link, profile: "Work", browser: "Chrome", condition: .contains, value: "gitlab"))
            } == .verificationFailed)
        // A pattern that misses the URL is reported as such, even if it would also hide a later rule.
        let later = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [
                Route(condition: .domain, value: "github.com", profile: "Default"),
                Route(condition: .domain, value: "docs.gitlab.com", profile: "Default"),
            ])
        #expect(
            code {
                _ = try operations(fixture, later).route(
                    RouteRequest(
                        url: link, profile: "Work", browser: "Chrome", condition: .contains, value: "gitlab"))
            } == .verificationFailed)
        // Updating a same-pattern rule that an earlier rule hides doesn't change where the URL goes.
        let hidden = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [
                Route(condition: .contains, value: "acme", profile: "Default", browser: paths.chrome),
                Route(condition: .domain, value: "github.com", profile: "Default"),
            ])
        #expect(
            code {
                _ = try operations(fixture, hidden).route(
                    RouteRequest(url: try url("https://github.com/acme"), profile: "H3"))
            } == .verificationFailed)
        #expect(
            code {
                _ = try operations(fixture, empty).route(
                    RouteRequest(url: link, profile: "Work", browser: "Chrome", condition: .contains))
            } == .invalidArgument)
        #expect(
            code {
                _ = try operations(fixture, empty).route(
                    RouteRequest(url: link, profile: "Work", value: "https://github.com"))
            } == .invalidArgument)
    }

    @Test func directoryIdentifiersWinOverCollidingDisplayNames() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser(name: "Google Chrome")
        try fixture.profiles([
            "Default": "Profile 2", "Profile 2": "Work", "Profile 3": "Ryan", "Profile 4": "Ryan",
        ])
        let operations = operations(
            fixture, Config(browser: chrome.path, defaultProfile: "Default", routes: []))
        #expect(try operations.resolveProfile("Profile 2", browser: chrome.path).directory == "Profile 2")
        #expect(try operations.resolveProfile("work", browser: chrome.path).directory == "Profile 2")
        #expect(try operations.resolveProfile("profile 3", browser: chrome.path).directory == "Profile 3")
        do {
            _ = try operations.resolveProfile("ryan", browser: chrome.path)
            Issue.record("An ambiguous name was accepted")
        } catch let error as OperationError {
            #expect(error.code == .ambiguousProfile)
            #expect(error.code.exitCode == 3)
            #expect(error.candidates.compactMap(\.profile) == ["Profile 3", "Profile 4"])
        }
        do {
            _ = try operations.resolveProfile("Nobody", browser: chrome.path)
            Issue.record("A missing profile was accepted")
        } catch let error as OperationError {
            #expect(error.code == .profileNotFound)
            #expect(error.candidates.count == 4)
        }
    }

    @Test func profilesAreResolvedWithinTheDestinationBrowser() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(browser: paths.helium, defaultProfile: "Default", routes: [])
        let link = try url("https://example.com")
        // Helium's profile name doesn't exist in Chrome, even though both have a "Profile 2" directory.
        #expect(
            code {
                _ = try operations(fixture, config).route(
                    RouteRequest(url: link, profile: "Helium Work", browser: "Chrome"))
            } == .profileNotFound)
        let helium = try operations(fixture, config).route(RouteRequest(url: link, profile: "Helium Work"))
        #expect(helium.config.routes[0].browser == nil)
        #expect(helium.config.routes[0].profile == "Profile 2")
        let chrome = try operations(fixture, config).route(
            RouteRequest(url: link, profile: "Profile 2", browser: "Chrome"))
        #expect(chrome.config.routes[0].browser == paths.chrome)
        #expect(
            Router(config: chrome.config).route(url: link)
                == Destination(browser: paths.chrome, profile: "Profile 2"))
    }

    @Test func editsLeaveLegacyRulesAndAChromeRuleWithAHeliumDefaultAlone() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(
            browser: paths.helium, defaultProfile: "Ryan",
            routes: [
                Route(condition: .domain, value: "gitlab.com", profile: "Work", browser: paths.chrome),
                Route(condition: .domain, value: "youtube.com", profile: "H3"),
            ])
        let operations = operations(fixture, config)
        #expect(operations.rules().map(\.profileStatus) == [.ok, .ok])
        #expect(operations.rules().map(\.destination.profile) == ["Profile 2", "Profile 1"])
        let gitlab = operations.explain(try url("https://gitlab.com/acme"))
        #expect(gitlab.decision.destination.browser == paths.chrome)
        #expect(gitlab.decision.destination.profileName == "Work")
        let result = try operations.route(
            RouteRequest(url: try url("https://example.com/a"), profile: "Profile 1"))
        // Only the new rule is written with a directory; the others keep their saved values.
        #expect(result.config.routes.map(\.profile) == ["Work", "H3", "Profile 1"])
        #expect(result.config.defaultProfile == "Ryan")
        #expect(result.config.routes.map(\.browser) == [paths.chrome, nil, nil])
    }

    @Test func changingTheDefaultBrowserWaitsForInheritingRules() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [
                Route(condition: .domain, value: "youtube.com", profile: "Profile 2"),
                Route(condition: .domain, value: "gitlab.com", profile: "Profile 2", browser: paths.chrome),
            ])
        #expect(
            code { _ = try operations(fixture, config).setDefault(browser: "Chrome", profile: nil) }
                == .invalidArgument)
        do {
            _ = try operations(fixture, config).setDefault(browser: "Chrome", profile: "Work")
            Issue.record("Inheriting rules were silently moved to another browser")
        } catch let error as OperationError {
            #expect(error.code == .inheritingRules)
            #expect(error.code.exitCode == 3)
            #expect(error.candidates.map(\.index) == [1])
            #expect(error.candidates.first?.suggestion?.contains("rules update 1 --browser") == true)
        }
        let pinned = try operations(fixture, config).updateRule(
            at: 1, RuleUpdate(profile: "Profile 2", browser: .browser(paths.helium)))
        let result = try operations(fixture, pinned.config).setDefault(browser: "Chrome", profile: "Work")
        #expect(result.config.browser == paths.chrome)
        #expect(result.config.defaultProfile == "Profile 2")
        #expect(
            Router(config: result.config).route(url: try url("https://youtube.com"))
                == Destination(browser: paths.helium, profile: "Profile 2"))
        let profileOnly = try operations(fixture, config).setDefault(browser: nil, profile: "H3")
        #expect(profileOnly.config.defaultProfile == "Profile 1")
        #expect(profileOnly.config.routes == config.routes)
    }

    @Test func updatesRequireAProfileForANewBrowserAndKeepRulesReachable() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [
                Route(condition: .domain, value: "github.com", profile: "Default"),
                Route(condition: .domain, value: "gitlab.com", profile: "Default"),
            ])
        let operations = operations(fixture, config)
        #expect(
            code { _ = try operations.updateRule(at: 1, RuleUpdate(browser: .browser("Chrome"))) }
                == .invalidArgument)
        #expect(
            code { _ = try operations.updateRule(at: 3, RuleUpdate(profile: "Default")) } == .ruleNotFound)
        #expect(
            code { _ = try operations.updateRule(at: 2, RuleUpdate(value: "github.com")) }
                == .verificationFailed)
        #expect(code { _ = try operations.updateRule(at: 1, RuleUpdate(value: "com")) } == .wouldShadow)
        #expect(
            code { _ = try operations.updateRule(at: 1, RuleUpdate(value: "https://github.com")) }
                == .invalidArgument)
        let allowed = try operations.updateRule(at: 1, RuleUpdate(value: "com", allowShadowing: true))
        #expect(allowed.config.routes[0].value == "com")
        let moved = try operations.updateRule(at: 2, RuleUpdate(profile: "Work", browser: .browser("Chrome")))
        #expect(moved.config.routes[1].browser == paths.chrome)
        #expect(moved.config.routes[1].profile == "Profile 2")
        let unchanged = try operations.updateRule(at: 1, RuleUpdate(profile: "Ryan"))
        #expect(!unchanged.changed)
    }

    @Test func movesAndRemovalsReportRecentLinksThatWouldChange() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [
                Route(condition: .domain, value: "github.com", profile: "Default"),
                Route(condition: .contains, value: "acme", profile: "Profile 2", browser: paths.chrome),
            ])
        let entries = [
            "https://github.com/acme/api", "https://github.com/other", "https://github.com/acme/api",
        ].map {
            HistoryEntry(
                id: HistoryEntry.makeID(), time: Date(), url: $0, source: .rule, browser: paths.helium,
                profile: "Default", result: .launched)
        }
        let operations = operations(fixture, config)
        let moved = try operations.moveRule(from: 2, to: 1)
        #expect(moved.config.routes.map(\.value) == ["acme", "github.com"])
        let changes = operations.historyChanges(to: moved.config, entries: entries)
        #expect(changes.map(\.entry.url) == ["https://github.com/acme/api"])
        #expect(changes.first?.before.rule?.index == 1)
        #expect(changes.first?.after.destination.browser == paths.chrome)
        let removed = try operations.removeRule(at: 1)
        #expect(removed.config.routes.map(\.value) == ["acme"])
        // github.com/other still opens in Helium · Default through the default destination.
        #expect(
            operations.historyChanges(to: removed.config, entries: entries).map(\.entry.url) == [
                "https://github.com/acme/api"
            ])
        #expect(!(try operations.moveRule(from: 1, to: 1)).changed)
        #expect(code { _ = try operations.moveRule(from: 1, to: 3) } == .ruleNotFound)
    }

    @Test func explainListsLaterRulesThatAreNeverReached() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let config = Config(
            browser: paths.helium, defaultProfile: "Default",
            routes: [
                Route(condition: .domain, value: "github.com", profile: "Profile 9"),
                Route(condition: .contains, value: "acme", profile: "Default"),
            ])
        let explanation = operations(fixture, config).explain(try url("https://github.com/acme"))
        #expect(explanation.decision.rule == RuleReference(index: 1, condition: .domain, value: "github.com"))
        #expect(explanation.decision.profileStatus == .missing)
        #expect(explanation.decision.destination.profileName == nil)
        #expect(explanation.alsoMatches == [RuleReference(index: 2, condition: .contains, value: "acme")])
        let unmatched = operations(fixture, config).explain(try url("https://example.com"))
        #expect(unmatched.decision.rule == nil)
        #expect(unmatched.decision.destination.profileName == "Ryan")
        let missingBrowser = Config(browser: "/Missing/Helium.app", defaultProfile: "Default", routes: [])
        #expect(
            operations(fixture, missingBrowser).explain(try url("https://example.com")).decision.profileStatus
                == .unavailable)
    }

    @Test func browsersResolveByPathBundleIdentifierAndName() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let paths = try browsers(fixture)
        let operations = operations(
            fixture, Config(browser: paths.helium, defaultProfile: "Default", routes: []))
        for query in [
            paths.chrome, paths.chrome + "/", "com.google.chrome", "Chrome", "google chrome",
            "Google Chrome.app",
        ] {
            #expect(try operations.resolveBrowser(query).path == paths.chrome)
        }
        #expect(try operations.resolveBrowser("helium").bundleIdentifier == "net.imput.helium")
        #expect(code { _ = try operations.resolveBrowser("Firefox") } == .browserNotFound)
        #expect(
            code { _ = try operations.resolveBrowser(fixture.root.appendingPathComponent("Nope.app").path) }
                == .browserNotFound)
        let copies = fixture.root.appendingPathComponent("Copies")
        try FileManager.default.createDirectory(at: copies, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: paths.chrome), to: copies.appendingPathComponent("Google Chrome.app"))
        let both = RuleOperations(
            config: Config(browser: paths.helium, defaultProfile: "Default", routes: []),
            catalog: BrowserCatalog(
                homeDirectory: fixture.root, applicationDirectories: [fixture.root, copies]))
        #expect(code { _ = try both.resolveBrowser("Chrome") } == .ambiguousBrowser)
        #expect(code { _ = try both.resolveBrowser("com.google.Chrome") } == .ambiguousBrowser)
        #expect(try both.resolveBrowser(paths.chrome).path == paths.chrome)
    }

    @Test(arguments: [
        (Condition.domain, "github.com", Condition.domain, "docs.github.com", true),
        (.domain, "github.com", .domain, "GitHub.com", true),
        (.domain, "docs.github.com", .domain, "github.com", false),
        (.domain, "github.com", .domain, "notgithub.com", false),
        (.domain, "github.com", .exact, "https://docs.github.com/a", true),
        (.domain, "github.com", .contains, "github.com", false),
        (.contains, "acme", .contains, "github.com/acme", true),
        (.contains, "github.com/acme", .contains, "acme", false),
        (.contains, "github", .domain, "github.com", true),
        (.contains, "acme", .exact, "https://github.com/ACME", true),
        (.exact, "https://a.com", .exact, "HTTPS://A.COM", true),
        (.exact, "https://a.com", .domain, "a.com", false),
        (.contains, "", .contains, "acme", false),
    ])
    func shadowing(earlier: Condition, first: String, later: Condition, second: String, covered: Bool) {
        #expect(
            Shadowing.covers(
                Route(condition: earlier, value: first), Route(condition: later, value: second)) == covered)
    }
}
