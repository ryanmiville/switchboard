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
        #expect(p.error == TabError.notWeb.description)
        Thread.sleep(forTimeInterval: 0.2)
        #expect(scene.temporary.recordedLaunches().isEmpty)
    }

    @Test func arrowsWrapAndAMissingPermissionOffersItsSettings() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        p.moveSelection(by: -1)
        #expect(p.selected == p.shown.count - 1)
        p.moveSelection(by: 1)
        #expect(p.selected == 0)
        p.tabRead(.failure(.automationDenied), browserID: nil, installed: scene.browsers.installed())
        #expect(p.needsPermission)
    }

    func id(_ locator: String, _ scene: SceneHome) throws -> String {
        try #require(scene.browsers.installed().first { $0.locator == locator }).id
    }

    @Test func theProfileTheWindowTitleNamesIsLeftOut() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        p.tabRead(
            .success(BrowserTab(link: "https://example.com/a", windowTitle: "Example - Helium - Ryan")),
            browserID: try id(scene.helium, scene), installed: scene.browsers.installed())
        #expect(p.current == Destination(browser: scene.helium, profile: "Default"))
        #expect(!p.shown.map(\.label).contains("Helium · Ryan"))
        #expect(p.shown.count == 4)
        #expect(p.link == "https://example.com/a")
    }

    @Test func theSameProfileNameInAnotherBrowserStays() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        p.tabRead(
            .success(BrowserTab(link: "https://example.com", windowTitle: "Docs - Google Chrome - Work")),
            browserID: try id(scene.chrome, scene), installed: scene.browsers.installed())
        #expect(p.shown.map(\.label).contains("Helium · Work"))
        #expect(!p.shown.map(\.label).contains("Google Chrome · Work"))
    }

    @Test func aTitleNamingNoProfileLeavesEveryDestination() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        p.tabRead(
            .success(BrowserTab(link: "https://example.com", windowTitle: "Home - Helium")),
            browserID: try id(scene.helium, scene), installed: scene.browsers.installed())
        #expect(p.current == nil)
        #expect(p.shown.count == 5)
    }

    @Test func aBrowserWithOneProfileIsThatProfile() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        let p = picker(scene)
        let only = p.all.filter { $0.label == "Helium · Work" }
        let current = QuickSwitch.current(
            windowTitle: nil, browserID: try id(scene.helium, scene), installed: scene.browsers.installed(),
            choices: only)
        #expect(current == Destination(browser: scene.helium, profile: "Profile 1"))
    }

    @Test func typingNarrowsTheDestinationsByProfileOrBrowserName() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        p.moveSelection(by: 2)
        p.setQuery("chrome")
        #expect(p.selected == 0)
        #expect(p.shown.map(\.browserName) == ["Google Chrome", "Google Chrome", "Google Chrome"])
        p.setQuery("WORK hel")
        #expect(p.shown.map(\.label) == ["Helium · Work"])
        p.setQuery("nothing like this")
        #expect(p.shown.isEmpty)
    }

    @Test func commandNumbersOpenTheShownDestinationsInOrder() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        #expect(p.number(1) == 0)
        #expect(p.number(5) == 4)
        #expect(p.number(6) == nil)
        #expect(p.number(0) == nil)
        p.setQuery("work")
        #expect(p.number(2) == 1)
        #expect(p.number(3) == nil)
    }

    @Test func withNoLinkReadOpeningOpensNothing() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var p = picker(scene)
        p.link = ""
        let opened = p.open(
            0, browsers: scene.browsers, history: scene.temporary.historyStore, now: Timestamp(0))
        #expect(opened == nil)
        #expect(p.error == TabError.unsupportedBrowser.description)
        Thread.sleep(forTimeInterval: 0.2)
        #expect(scene.temporary.recordedLaunches().isEmpty)
    }
}

struct ShortcutKeyTests {
    @Test func shortcutTextBecomesAKeyCodeAndCarbonModifiersAndBack() throws {
        let chord = try #require(KeyChord(Shortcut("ctrl+alt+space")))
        #expect(chord == KeyChord(keyCode: 49, modifiers: KeyChord.control | KeyChord.option))
        #expect(chord.shortcut == Shortcut("ctrl+alt+space"))
        #expect(chord.display == "⌃⌥Space")
        #expect(KeyChord(Shortcut("Cmd+Shift+L"))?.shortcut == Shortcut("shift+cmd+l"))
        #expect(KeyChord(Shortcut("hyper+x")) == nil)
        #expect(KeyChord(Shortcut("ctrl+nope")) == nil)
        #expect(KeyChord(Shortcut("shift+a"))?.isValid == false, "shift alone would take a typed key")
    }

    @Test func theCurrentAppsCarbonShortcutRoundTrips() throws {
        let picker = try JSONDecoder().decode(
            PickerSettings.self,
            from: Data(#"{"shortcut":{"key":"Space","keyCode":49,"modifiers":6144}}"#.utf8))
        #expect(KeyChord(picker.shortcut) == KeyChord(keyCode: 49, modifiers: 6144))
    }
}
