import Foundation
import SwitchboardCore
import SwitchboardFixtures
import Testing

@testable import SwitchboardEditor

struct RecentLinksTests {
    func entry(_ url: String, _ source: History.Source, browser: String, profile: String) -> History.Entry {
        History.Entry(
            id: History.newID(), time: Timestamp(0).rfc3339, url: url, source: source, browser: browser,
            profile: profile, result: .launched)
    }

    @Test func aLinkThatOpensShowsUpInRecentLinksNewestFirst() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        #expect(e.recent.isEmpty)
        #expect(Routing.receive("https://github.com/a", editor: &e, now: Timestamp(1)) == nil)
        #expect(Routing.receive("https://example.org/b", editor: &e, now: Timestamp(2)) == nil)
        #expect(e.recent.map(\.url) == ["https://example.org/b", "https://github.com/a"])
        #expect(e.recent.map(\.reason) == ["No rule matched, so the default", "Rule 1: Domain github.com"])
    }

    @Test func clearingHistoryEmptiesRecentLinks() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        _ = Routing.receive("https://github.com/a", editor: &e, now: Timestamp(1))
        #expect(e.recent.count == 1)
        e.clearHistory()
        #expect(e.recent.isEmpty)
        #expect(e.recentError == nil)
    }

    @Test func linksRecordedElsewhereShowUpWhenRecentLinksIsReadAgain() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        try e.history.append(entry("https://x.com", .picker, browser: scene.chrome, profile: "Default"))
        #expect(e.recent.isEmpty)
        e.loadRecent()
        #expect(e.recent.map(\.url) == ["https://x.com"])
    }

    @Test func aRuleForALinkMatchesItsDomainWithoutWww() throws {
        let draft = Draft.forLink(
            entry("https://www.Figma.com/file/a?t=1", .default, browser: "/A/Helium.app", profile: "Default"),
            defaultBrowser: "/A/Helium.app", firstProfile: "Profile 1")
        #expect(draft.isNew)
        #expect(draft.condition == .domain)
        #expect(draft.value == "figma.com")
        #expect(draft.browser == nil)
        #expect(
            draft.profile == "Profile 1", "a link that went where the rules sent it starts like a new rule")
        #expect(Draft.domain(of: "www.com") == "www.com")
    }

    @Test func aRuleForALinkChosenInQuickSwitchKeepsWhereItWasSent() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        let other = Draft.forLink(
            entry("https://figma.com/a", .picker, browser: scene.chrome, profile: "Profile 3"),
            defaultBrowser: scene.helium, firstProfile: "Default")
        #expect(other.browser == scene.chrome)
        #expect(other.profile == "Profile 3")
        let same = Draft.forLink(
            entry("https://figma.com/a", .picker, browser: scene.helium, profile: "Profile 1"),
            defaultBrowser: scene.helium, firstProfile: "Default")
        #expect(same.browser == nil, "the default browser is inherited, as the rule sheet chooses it")
        #expect(same.profile == "Profile 1")
        var draft = other
        #expect(draft.validated() != nil)
    }

    @Test func aRuleForALocalFileMatchesTheWholeLink() {
        let draft = Draft.forLink(
            entry("file:///Users/r/a.html", .default, browser: "/A/Helium.app", profile: "Default"),
            defaultBrowser: "/A/Helium.app", firstProfile: "Default")
        #expect(draft.condition == .exact)
        #expect(draft.value == "file:///Users/r/a.html")
    }
}
