import Foundation
import Testing

@testable import SwitchboardCore

struct RouterTests {
    @Test(arguments: [
        ("https://GITHUB.com/a", Condition.contains, "github.com", "Work"),
        ("https://example.com/?next=github.com", .contains, "github.com", "Work"),
        ("https://github.com.example.com", .contains, "github.com", "Work"),
        ("https://example.com/A", .exact, "HTTPS://EXAMPLE.COM/a", "Work"),
        ("https://example.com/a/b", .exact, "https://example.com/a", "Default"),
        ("https://example.com", .contains, "", "Default"),
        ("https://github.com/Case", .domain, "GITHUB.COM", "Work"),
        ("https://docs.github.com/path", .domain, "github.com", "Work"),
        ("https://github.com.example.com", .domain, "github.com", "Default"),
        ("https://notgithub.com", .domain, "github.com", "Default"),
        ("https://example.com/?next=github.com", .domain, "github.com", "Default"),
        ("https://example.com", .domain, "", "Default"),
    ])
    func matching(url: String, condition: Condition, value: String, expected: String) throws {
        let config = Config(
            browser: "/fixture.app", defaultProfile: "Default",
            routes: [Route(condition: condition, value: value, profile: "Work")]
        )
        #expect(Router(config: config).route(url: try #require(URL(string: url))).profile == expected)
    }

    @Test func firstMatchWins() throws {
        let config = Config(
            browser: "/fixture.app", defaultProfile: "Default",
            routes: [Route(value: "example", profile: "First"), Route(value: "example", profile: "Second")]
        )
        #expect(
            Router(config: config).route(url: try #require(URL(string: "https://example.com"))).profile
                == "First")
    }

    @Test func rulesChooseBrowserAndProfileWhileUnmatchedURLsUseDefaults() throws {
        let config = Config(
            browser: "/Applications/Helium.app", defaultProfile: "Default",
            routes: [
                Route(
                    condition: .domain, value: "gitlab.com", profile: "Profile 3",
                    browser: "/Applications/Google Chrome.app"),
                Route(condition: .domain, value: "youtube.com", profile: "Profile 1"),
            ]
        )
        let router = Router(config: config)
        #expect(
            router.route(url: try #require(URL(string: "https://gitlab.com/example")))
                == Destination(browser: "/Applications/Google Chrome.app", profile: "Profile 3"))
        #expect(
            router.route(url: try #require(URL(string: "https://youtube.com/example")))
                == Destination(browser: "/Applications/Helium.app", profile: "Profile 1"))
        let unmatched = router.decision(url: try #require(URL(string: "https://example.com")))
        #expect(unmatched.destination == Destination(browser: "/Applications/Helium.app", profile: "Default"))
        #expect(unmatched.route == nil)
    }
}
