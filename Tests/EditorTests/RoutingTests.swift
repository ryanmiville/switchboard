import Foundation
import SwitchboardCore
import SwitchboardFixtures
import Testing

@testable import SwitchboardEditor

struct RoutingTests {
    @Test func aLinkOpensInTheMatchingRulesBrowserAndProfileAndIsRecorded() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        let link = "https://gitlab.ACME.com/a?token=1"
        #expect(Routing.receive(link, editor: &e, now: Timestamp(100)) == nil)
        #expect(scene.temporary.waitForLaunches(1) == [["--profile-directory=Profile 2", link]])
        let entry = try #require(try e.history.entries().first)
        #expect(entry.browser == scene.chrome)
        #expect(entry.rule?.index == 2)
        #expect(entry.source == .rule)
    }

    @Test func pendingEditsAreSavedBeforeALinkIsRouted() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        e.selectDefaultProfile("Profile 1")
        #expect(Routing.receive("https://example.org", editor: &e, now: Timestamp(0)) == nil)
        #expect(try e.store.load().config.defaultProfile == "Profile 1")
        #expect(scene.temporary.waitForLaunches(1).first?.first == "--profile-directory=Profile 1")
    }

    @Test func aLinkThatCantOpenReportsWhyAndOpensNothingElse() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        e.edit { $0.rules[0].profile = "Profile 9" }
        // The edit can't be saved (the profile doesn't exist), so the link isn't routed with it.
        let reason = Routing.receive("https://github.com/x", editor: &e, now: Timestamp(0))
        #expect(reason == ProfileError.missing("Profile 9").description)
        #expect(
            Routing.receive("github.com", editor: &e, now: Timestamp(0)) == LaunchError.invalidURL.description
        )
        Thread.sleep(forTimeInterval: 0.2)
        #expect(scene.temporary.recordedLaunches().isEmpty)
    }

    @Test func testingALinkShowsTheRuleItMatchesWithoutOpeningIt() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        let e = editor(scene)
        #expect(
            Routing.describe("https://github.com/acme/api", editor: e).text
                == "Rule 1 (domain github.com) → Helium · Work")
        #expect(
            Routing.describe("https://example.org", editor: e).text
                == "No rule matches → the default, Helium · Ryan")
        #expect(!Routing.describe("github.com", editor: e).ok)
        #expect(scene.temporary.recordedLaunches().isEmpty)
    }

    @Test func aLinkOnlyLaunchQuitsAfterItsLatestLink() {
        var s = RoutingSession()
        let first = s.receiveLink()
        s.finishLaunching(atLogin: false)
        let second = s.receiveLink()
        #expect(!s.shouldQuit(after: first))
        #expect(s.shouldQuit(after: second))
    }

    @Test func openingSettingsOrLaunchingAtLoginKeepsTheAppRunning() {
        var s = RoutingSession()
        var t = s.receiveLink()
        s.finishLaunching(atLogin: true)
        #expect(!s.shouldQuit(after: t))

        s = RoutingSession()
        t = s.receiveLink()
        s.finishLaunching(atLogin: false)
        s.stayResident()
        #expect(!s.shouldQuit(after: t))

        s = RoutingSession()
        s.finishLaunching(atLogin: false)
        t = s.receiveLink()
        #expect(!s.shouldQuit(after: t), "a normal launch is resident")
    }
}

struct PickerTests {
    func picker(_ scene: SceneHome) -> PickerState {
        var p = PickerState()
        p.refresh(store: scene.temporary.configStore, browsers: scene.browsers)
        p.link = "https://github.com/acme/api/pull/12"
        return p
    }

    @Test func favoritesComeFirstWithTheirSavedNames() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        let p = picker(scene)
        #expect(
            p.shown.map(\.label) == [
                "Helium · Ryan", "Google Chrome · Chrome Ryan", "Google Chrome · Side project",
                "Google Chrome · Work",
                "Helium · Work",
            ])
        #expect(p.shown[0].favorite)
        #expect(p.favorite(1) == 0)
        #expect(p.favorite(2) == nil)
    }

    @Test func hiddenDestinationsAreLeftOut() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        p.settings.destinations = [Destination(browser: scene.chrome, profile: "Profile 2")]
        #expect(p.shown.map(\.label) == ["Google Chrome · Work"])
        p.settings.destinations = []
        #expect(p.shown.isEmpty)
    }

    @Test func openingADestinationLaunchesThatProfileAndRecordsItAsAPick() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        let opened = p.open(
            3, browsers: scene.browsers, history: scene.temporary.historyStore, now: Timestamp(5))
        #expect(opened == Destination(browser: scene.chrome, profile: "Profile 2"))
        #expect(scene.temporary.waitForLaunches(1) == [["--profile-directory=Profile 2", p.link]])
        #expect(try scene.temporary.historyStore.entries().first?.source == .picker)
    }

    @Test func aFavoriteThatIsGoneShowsWhyAndOpensNothing() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        p.settings.favorites.append(Favorite(browser: scene.helium, profile: "Profile 9", name: "Old work"))
        p.all = QuickSwitch.choices(scene.browsers.installed(), p.settings)
        let gone = try #require(p.shown.firstIndex { $0.profileName == "Old work" })
        #expect(p.shown[gone].error != nil)
        let r1 = p.open(
            gone, browsers: scene.browsers, history: scene.temporary.historyStore, now: Timestamp(0))
        #expect(r1 == nil)
        #expect(p.error == p.shown[gone].error)
        p.link = "github.com"
        let r2 = p.open(0, browsers: scene.browsers, history: scene.temporary.historyStore, now: Timestamp(0))
        #expect(r2 == nil)
        #expect(p.error == "Enter a complete HTTP or HTTPS link, such as https://example.com.")
        Thread.sleep(forTimeInterval: 0.2)
        #expect(scene.temporary.recordedLaunches().isEmpty)
    }

    @Test func starringADestinationAddsItAsAFavoriteAndArrowsWrap() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        let r3 = p.toggleFavorite(3, browsers: scene.browsers)
        let settings = try #require(r3)
        #expect(settings.favorites.map(\.name) == ["Ryan", "Work"])
        #expect(p.shown[1].favorite)
        p.moveSelection(by: -1)
        #expect(p.selected == p.shown.count - 1)
        p.moveSelection(by: 1)
        #expect(p.selected == 0)
        p.tabRead(.failure(.automationDenied))
        #expect(p.needsPermission)
    }
}
