import Foundation
import SwitchboardCore
import SwitchboardFixtures
import Testing

@testable import SwitchboardEditor

func editor(_ scene: SceneHome) -> Editor {
    Editor(
        home: scene.home, store: scene.temporary.configStore, history: scene.temporary.historyStore,
        browsers: scene.browsers)
}

struct EditorTests {
    @Test func aFileChangedElsewhereReloadsWhenNothingIsPending() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        var other = e.config
        other.defaultProfile = "Profile 1"
        try e.store.save(other, expecting: try e.store.currentRevision())
        let r1 = e.checkExternal()
        #expect(r1)
        #expect(e.config.defaultProfile == "Profile 1")
        #expect(!e.conflict)
    }

    @Test func aFileChangedElsewhereWithPendingEditsIsAConflictThatKeepsBoth() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        e.selectDefaultProfile("Profile 1")
        var other = try e.store.load().config
        other.rules.removeAll()
        try e.store.save(other, expecting: try e.store.currentRevision())
        let theirs = try Data(contentsOf: e.store.url)

        let r2 = e.checkExternal()
        #expect(r2)
        #expect(e.conflict)
        #expect(e.error == Editor.conflictMessage)
        let r3 = e.flush()
        #expect(!r3, "a conflict never saves on its own")
        #expect(try Data(contentsOf: e.store.url) == theirs)
        #expect(e.config.defaultProfile == "Profile 1", "the edits are still here")

        let r4 = e.keepMine()
        #expect(r4)
        #expect(try e.store.load().config.defaultProfile == "Profile 1")
        #expect(try e.store.load().config.rules.count == 4)
    }

    @Test func anUnreadableFileIsNeverReplacedAndEditsAreRefused() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        try Data(#"{"browser": "#.utf8).write(to: scene.home.configFile)
        var e = editor(scene)
        #expect(e.loadError?.contains("line 1, column 13") == true)
        e.selectDefaultProfile("Profile 1")
        #expect(!e.hasUnsavedChanges)
        let r5 = e.flush()
        #expect(!r5)
        #expect(try Data(contentsOf: e.store.url) == Data(#"{"browser": "#.utf8))
    }

    @Test func aNewDefaultBrowserStartsOnItsFirstProfileAndSavesWithoutAsking() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        e.selectDefaultBrowser(scene.chrome)
        #expect(e.config.defaultProfile == "Default")
        #expect(
            e.config.rules.map(\.profile) == ["Default", "Profile 2", "Default", "Profile 3"],
            "rules that inherit the browser move to its first profile; rules with a browser keep theirs")
        let r6 = e.flush()
        #expect(r6, "nothing is left to choose")
        #expect(e.profileError == nil)
    }

    @Test func aDefaultBrowserWithNoDefaultProfileStartsOnTheFirstOneItsMenuLists() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let helium = try fixture.installBrowser(.helium, name: "Helium", profiles: [("Default", "Ryan")])
        let chrome = try fixture.installBrowser(
            .chrome, name: "Google Chrome", profiles: [("Profile 4", "Work"), ("Profile 7", "Home")])
        try FileManager.default.createDirectory(
            at: fixture.home.configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"browser":"\#(helium)","defaultProfile":"Default"}"#.utf8).write(
            to: fixture.home.configFile)
        var e = Editor(
            home: fixture.home, store: fixture.configStore, history: fixture.historyStore,
            browsers: fixture.browsers)
        e.selectDefaultBrowser(chrome)
        #expect(e.config.defaultProfile == "Profile 7", "Home sorts before Work, as the menu lists them")
    }

    @Test func anEditSavesAfterTheAutosaveDelayAndNotBefore() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        e.setHistoryEnabled(false)
        let r7 = e.poll(now: 10)
        #expect(r7 == Editor.autosaveDelay)
        let r8 = e.poll(now: 10.2)
        #expect(r8 != nil)
        #expect(try e.store.load().config.history == nil)
        let r9 = e.poll(now: 10.6)
        #expect(r9 == nil)
        #expect(try e.store.load().config.history == HistorySettings(enabled: false))
        #expect(!e.hasUnsavedChanges)
    }

    @Test func savesStoreEachProfileAsItsDirectoryInItsOwnBrowser() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        // "Work" is Profile 1 in Helium and Profile 2 in Chrome.
        e.edit { c in
            c.defaultProfile = "Work"
            c.rules[1].profile = "Work"
        }
        let r10 = e.flush()
        #expect(r10)
        let saved = try e.store.load().config
        #expect(saved.defaultProfile == "Profile 1")
        #expect(saved.rules[1].profile == "Profile 2")
        #expect(e.profileName(browser: scene.chrome, profile: "Profile 2") == "Work")
        #expect(e.profileName(browser: scene.helium, profile: "Profile 9") == "Profile 9 (unavailable)")
    }

    @Test func rulesMoveDeleteAndCommitByID() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        var e = editor(scene)
        let first = e.config.rules[0].id
        e.moveRule(first, to: 2)
        #expect(
            e.config.rules.map(\.value) == [
                "acme", "docs.github.com", "github.com", "https://example.com/login",
            ])
        e.moveRule(first, by: -1)
        #expect(e.config.rules[1].id == first)
        e.deleteRule(first)
        #expect(e.config.rules.count == 3)
        var draft = Draft.editing(e.config.rules[0])
        draft.value = "acme.com"
        draft.condition = .domain
        let validated = draft.validated()
        let committed = e.commitRule(try #require(validated))
        #expect(committed)
        #expect(e.config.rules[0].value == "acme.com")
        #expect(e.config.rules.count == 3)
    }

    @Test func doneRefusesARuleWithoutAProfileOrWithAPathAsADomain() {
        var draft = Draft.newRule()
        draft.value = "github.com/acme"
        draft.profile = "Default"
        let v1 = draft.validated()
        #expect(v1 == nil)
        #expect(draft.error?.hasPrefix("“github.com/acme” isn’t a domain.") == true)
        draft.value = "  "
        let v2 = draft.validated()
        #expect(v2 == nil)
        #expect(draft.error == "The pattern can’t be empty: empty patterns never match.")
        draft.value = "github.com"
        draft.profile = ""
        let v3 = draft.validated()
        #expect(v3 == nil)
        #expect(draft.error == "Choose a profile.")
    }

    @Test func changingADraftsBrowserStartsOnTheNewBrowsersFirstProfile() {
        var draft = Draft.newRule()
        draft.profile = "Profile 1"
        draft.selectBrowser(nil, defaultBrowser: "/A.app", firstProfile: "Default")
        #expect(draft.profile == "Profile 1", "the same browser keeps the profile")
        draft.selectBrowser("/B.app", defaultBrowser: "/A.app", firstProfile: "Profile 3")
        #expect(draft.profile == "Profile 3")
    }

    @Test func aNewRuleStartsOnTheDefaultBrowsersFirstProfile() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        let e = editor(scene)
        #expect(e.firstProfile(of: scene.chrome) == "Default")
        #expect(e.firstProfile(of: "") == "")
        var draft = Draft.newRule(profile: e.firstProfile(of: e.config.browser))
        draft.enterPattern("figma.com")
        #expect(draft.profile == "Default")
        #expect(draft.validated() != nil, "a new rule needs only a pattern")
    }

    @Test func theSwiftAppsSettingsFileOpensInPlaceAndSavesProfilesAsDirectories() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let helium = try fixture.installBrowser(.helium, name: "Helium", profiles: [("Default", "Ryan")])
        // As the previous Swift app saved it: `routes`, and profiles by their display names.
        try FileManager.default.createDirectory(
            at: fixture.home.configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(
            #"{"browser":"\#(helium)","defaultProfile":"Ryan","routes":[{"condition":"domain","value":"a.com","profile":"Ryan"}]}"#
                .utf8
        ).write(to: fixture.home.configFile)
        var e = Editor(
            home: fixture.home, store: fixture.configStore, history: fixture.historyStore,
            browsers: fixture.browsers)
        #expect(e.loadError == nil)
        #expect(e.config.rules.map(\.value) == ["a.com"])
        e.setHistoryEnabled(false)
        let flushed = e.flush()
        #expect(flushed)
        let saved = try fixture.configStore.load().config
        #expect(saved.rules.map(\.value) == ["a.com"])
        #expect(saved.defaultProfile == "Default", "saved as its directory")
    }

    @Test func theWatcherNoticesASaveMadeElsewhere() async throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        let changes = Counter()
        let watcher = FileWatcher(scene.home.configFile) { changes.increment() }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))
        var config = try scene.temporary.configStore.load()
        config.config.defaultProfile = "Profile 1"
        try scene.temporary.configStore.save(config.config, expecting: config.revision)
        for _ in 0..<40 where changes.value == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(changes.value >= 1)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
