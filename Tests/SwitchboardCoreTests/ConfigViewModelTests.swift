import Foundation
import Testing

@testable import SwitchboardCore

@MainActor
struct ConfigViewModelTests {
    private func model(_ fixture: Fixture) -> ConfigViewModel {
        ConfigViewModel(
            configURL: fixture.configURL, profileStore: BrowserProfiles(homeDirectory: fixture.root),
            browsers: [], autosaveDelay: 3600)
    }

    @Test func malformedConfigurationCannotBeOverwrittenByEditing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = Data("{ broken JSON".utf8)
        try original.write(to: fixture.configURL)
        let model = model(fixture)
        #expect(model.loadError != nil)
        model.addRoute()
        #expect(!model.flush())
        #expect(try Data(contentsOf: fixture.configURL) == original)
    }

    @Test func pendingEditsFlushImmediatelyAndLegacyNamesMigrate() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal", "Profile 1": "Work"])
        try Config(browser: browser.path, defaultProfile: "Work", routes: []).save(to: fixture.configURL)
        let model = model(fixture)
        #expect(model.config.defaultProfile == "Profile 1")
        model.addRoute()
        model.config.routes[0].value = "github.com"
        #expect(model.flush())
        #expect(try Config.load(from: fixture.configURL).routes.first?.profile == "Profile 1")
        try fixture.profiles(["Default": "Personal", "Profile 1": "Renamed"])
        model.reload()
        #expect(model.profileError == nil)
        #expect(model.config.routes.first?.profile == "Profile 1")
    }

    @Test func invalidProfileKeepsSavedFileAndEditsForRetry() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        try Config(browser: browser.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        let original = try Data(contentsOf: fixture.configURL)
        let model = model(fixture)
        model.config.defaultProfile = "Missing"
        #expect(!model.flush())
        #expect(model.profileError != nil)
        #expect(model.config.defaultProfile == "Missing")
        #expect(try Data(contentsOf: fixture.configURL) == original)
        model.config.defaultProfile = "Default"
        #expect(model.flush())
        #expect(model.profileError == nil)
    }

    @Test func repairedConfigCanBeReloaded() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try Data("bad".utf8).write(to: fixture.configURL)
        let model = model(fixture)
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        try Config(browser: browser.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        model.reload()
        #expect(model.loadError == nil)
        model.addRoute()
        #expect(model.flush())
    }

    @Test func failedAtomicSavePreservesFileAndAllowsRetry() throws {
        let fixture = try Fixture()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: fixture.root.path)
            fixture.cleanUp()
        }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        try Config(browser: browser.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        let original = try Data(contentsOf: fixture.configURL)
        let model = model(fixture)
        model.addRoute()
        model.config.routes[0].value = "example.com"
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.root.path)
        #expect(!model.flush())
        #expect(model.hasUnsavedChanges)
        #expect(model.saveError != nil)
        #expect(try Data(contentsOf: fixture.configURL) == original)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.root.path)
        #expect(model.flush())
        #expect(try Config.load(from: fixture.configURL).routes.first?.value == "example.com")
    }

    @Test func refreshingProfilesDoesNotDiscardPendingEdits() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        try Config(browser: browser.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        let model = model(fixture)
        model.addRoute()
        model.config.routes[0].value = "unsaved.example"
        model.refreshProfiles()
        #expect(model.config.routes.first?.value == "unsaved.example")
        #expect(model.hasUnsavedChanges)
        #expect(model.flush())
    }

    @Test func switchingBrowserRequiresAnExistingProfile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser()
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        try fixture.profiles(["Default": "Personal", "Profile 1": "Work"])
        try fixture.profiles(["Default": "Personal"], folder: "net.imput.helium")
        try Config(browser: chrome.path, defaultProfile: "Profile 1", routes: []).save(to: fixture.configURL)
        let model = model(fixture)
        model.config.browser = helium.path
        #expect(model.availableProfiles.map(\.directory) == ["Default"])
        #expect(!model.flush())
        #expect(try Config.load(from: fixture.configURL).browser == chrome.path)
        model.config.defaultProfile = "Default"
        #expect(model.flush())
        #expect(try Config.load(from: fixture.configURL).browser == helium.path)
    }

    @Test func rowBindingRemainsSafeAfterDeletionAndReordering() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = model(fixture)
        let first = Route(value: "first")
        let second = Route(value: "second")
        model.config.routes = [first, second]
        let binding = model.binding(for: second)
        model.moveRoute(second, by: -1)
        binding.wrappedValue.value = "still second"
        #expect(model.config.routes.first?.value == "still second")
        #expect(model.config.routes.last?.value == "first")
        model.deleteRoute(second)
        #expect(binding.wrappedValue.id == second.id)
        binding.wrappedValue.value = "late text-field write"
        #expect(model.config.routes.count == 1)
        #expect(model.config.routes[0].value == "first")
    }

    @Test func ruleBrowserChangeRequiresChoosingThatBrowsersProfile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser()
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        try fixture.profiles(["Default": "Chrome Work", "Profile 3": "Other Chrome"])
        try fixture.profiles(["Default": "Ryan"], folder: "net.imput.helium")
        try Config(browser: helium.path, defaultProfile: "Default", routes: [Route(value: "gitlab.com")])
            .save(to: fixture.configURL)
        let model = model(fixture)
        let original = try Data(contentsOf: fixture.configURL)
        model.selectBrowser(chrome.path, for: try #require(model.config.routes.first))
        #expect(model.config.routes.first?.profile == "")
        #expect(model.profiles(for: chrome.path).map(\.name) == ["Chrome Work", "Other Chrome"])
        #expect(model.availableProfiles.map(\.name) == ["Ryan"])
        #expect(!model.flush())
        #expect(try Data(contentsOf: fixture.configURL) == original)
        model.config.routes[0].profile = "Default"
        #expect(model.flush())
        let saved = try Config.load(from: fixture.configURL)
        #expect(saved.browser == helium.path)
        #expect(saved.defaultProfile == "Default")
        #expect(saved.routes.first?.browser == chrome.path)
        model.refreshProfiles()
        #expect(model.profiles(for: chrome.path).first?.name == "Chrome Work")
        #expect(model.availableProfiles.first?.name == "Ryan")
    }

    @Test func ruleSheetsKeepDraftsIsolatedAndCommitInPlace() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        let rules = [Route(value: "first"), Route(value: "second")]
        try Config(browser: browser.path, defaultProfile: "Default", routes: rules)
            .save(to: fixture.configURL)
        let model = model(fixture)
        let original = try Data(contentsOf: fixture.configURL)
        let selected = model.config.routes[0]
        var edit = RouteDraft(config: model.config, route: selected)
        edit.route.value = "edited"
        var addition = RouteDraft(config: model.config)
        addition.route.value = "new.example"
        // Creating, changing, and cancelling either sheet cannot trigger an autosave.
        #expect(!model.hasUnsavedChanges)
        #expect(model.config.routes[0].value == "first")
        #expect(model.flush())
        #expect(try Data(contentsOf: fixture.configURL) == original)
        #expect(model.commitRoute(edit))
        #expect(model.config.routes.map(\.value) == ["edited", "second"])
        #expect(model.config.routes[0].id == selected.id)
        #expect(model.commitRoute(addition))
        #expect(model.config.routes.map(\.value) == ["edited", "second", "new.example"])
        #expect(!model.commitRoute(addition))
        #expect(model.flush())
        #expect(
            try Config.load(from: fixture.configURL).routes.map(\.value) == [
                "edited", "second", "new.example",
            ])
        model.deleteRoute(selected)
        #expect(!model.commitRoute(edit))
    }

    @Test func draftBrowserDiscoveryDoesNotSaveOrReuseAnotherBrowsersProfile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser()
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        try fixture.profiles(["Default": "Chrome Work"])
        try fixture.profiles(["Default": "Ryan"], folder: "net.imput.helium")
        try Config(browser: helium.path, defaultProfile: "Default", routes: [Route(value: "gitlab.com")])
            .save(to: fixture.configURL)
        let model = model(fixture)
        var draft = RouteDraft(config: model.config, route: model.config.routes[0])
        draft.selectBrowser(helium.path, defaultBrowser: model.config.browser)
        #expect(draft.route.profile == "Default")
        draft.selectBrowser(chrome.path, defaultBrowser: model.config.browser)
        #expect(draft.route.profile.isEmpty)
        #expect(try model.discoverProfiles(for: chrome.path).map(\.name) == ["Chrome Work"])
        #expect(model.availableProfiles.map(\.name) == ["Ryan"])
        #expect(!model.hasUnsavedChanges)
        draft.route.profile = "Default"
        #expect(model.commitRoute(draft))
        #expect(model.flush())
        let saved = try Config.load(from: fixture.configURL)
        #expect(saved.routes.first?.browser == chrome.path)
        #expect(saved.browser == helium.path)
        #expect(saved.routes.first?.profile == "Default")
    }

    @Test func draftSelectsTheOnlyProfileOfANewBrowser() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser()
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        try fixture.profiles(["Profile 1": "Chrome Work"])
        try fixture.profiles(["Default": "Ryan", "Profile 2": "H3"], folder: "net.imput.helium")
        try Config(browser: helium.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        let model = model(fixture)
        var draft = RouteDraft(config: model.config)
        draft.selectBrowser(chrome.path, defaultBrowser: model.config.browser)
        #expect(draft.route.profile.isEmpty)
        draft.selectOnlyProfile(in: try model.discoverProfiles(for: chrome.path))
        #expect(draft.route.profile == "Profile 1")
        draft.selectBrowser(nil, defaultBrowser: model.config.browser)
        draft.selectOnlyProfile(in: try model.discoverProfiles(for: helium.path))
        #expect(draft.route.profile.isEmpty)
        var stale = RouteDraft(
            config: model.config, route: Route(value: "a", profile: "Profile 9", browser: chrome.path))
        stale.selectOnlyProfile(in: try model.discoverProfiles(for: chrome.path))
        #expect(stale.route.profile == "Profile 9")
        #expect(!model.hasUnsavedChanges)
    }

    @Test func dragReorderingPreservesIdentityAndGlobalPriority() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = model(fixture)
        let rules = [Route(value: "one"), Route(value: "two"), Route(value: "three")]
        model.config.routes = rules
        model.moveRoute(id: rules[0].id, toInsertionIndex: 3)
        #expect(model.config.routes.map(\.id) == [rules[1].id, rules[2].id, rules[0].id])
        model.moveRoute(id: rules[0].id, toInsertionIndex: 0)
        #expect(model.config.routes == rules)
        model.moveRoute(id: rules[0].id, toInsertionIndex: 1)
        model.moveRoute(id: UUID(), toInsertionIndex: 0)
        model.moveRoute(id: rules[0].id, toInsertionIndex: 4)
        #expect(model.config.routes == rules)
    }

    @Test func externalChangesReloadWhenNothingIsPending() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal", "Profile 1": "Work"])
        try Config(browser: browser.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        let model = model(fixture)
        model.checkForExternalChanges()
        #expect(model.config.routes.isEmpty)
        try Config(
            browser: browser.path, defaultProfile: "Default",
            routes: [Route(condition: .domain, value: "github.com", profile: "Profile 1")]
        ).save(to: fixture.configURL)
        model.checkForExternalChanges()
        #expect(model.config.routes.map(\.value) == ["github.com"])
        #expect(!model.hasUnsavedChanges)
        #expect(!model.hasConflict)
        model.addRoute()
        model.config.routes[1].value = "gitlab.com"
        #expect(model.flush())
        #expect(try Config.load(from: fixture.configURL).routes.map(\.value) == ["github.com", "gitlab.com"])
    }

    @Test func externalChangesNeverOverwriteOrDiscardPendingEdits() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        try Config(browser: browser.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        let model = model(fixture)
        model.addRoute()
        model.config.routes[0].value = "pending.example"
        try Config(
            browser: browser.path, defaultProfile: "Default", routes: [Route(value: "external.example")]
        )
        .save(to: fixture.configURL)
        let external = try Data(contentsOf: fixture.configURL)
        model.checkForExternalChanges()
        #expect(model.hasConflict)
        #expect(model.saveError != nil)
        #expect(model.config.routes.map(\.value) == ["pending.example"])
        #expect(!model.flush())
        #expect(try Data(contentsOf: fixture.configURL) == external)
        #expect(model.keepChangesOverExternalEdits())
        #expect(!model.hasConflict)
        #expect(try Config.load(from: fixture.configURL).routes.map(\.value) == ["pending.example"])
    }

    @Test func aConflictingSaveKeepsEditsUntilTheSavedSettingsAreChosen() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        try Config(browser: browser.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        let model = model(fixture)
        model.addRoute()
        model.config.routes[0].value = "pending.example"
        try Config(
            browser: browser.path, defaultProfile: "Default", routes: [Route(value: "external.example")]
        )
        .save(to: fixture.configURL)
        let external = try Data(contentsOf: fixture.configURL)
        #expect(!model.flush())
        #expect(model.hasConflict)
        #expect(model.hasUnsavedChanges)
        #expect(try Data(contentsOf: fixture.configURL) == external)
        model.reload()
        #expect(!model.hasConflict)
        #expect(model.saveError == nil)
        #expect(model.config.routes.map(\.value) == ["external.example"])
        #expect(!model.hasUnsavedChanges)
    }

    @Test func theWatcherFollowsAtomicReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        try Config(browser: browser.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        let model = model(fixture)
        model.startWatchingConfig()
        try ConfigStore(url: fixture.configURL).save(
            Config(browser: browser.path, defaultProfile: "Default", routes: [Route(value: "github.com")]),
            expecting: nil)
        let deadline = Date().addingTimeInterval(5)
        while model.config.routes.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(model.config.routes.map(\.value) == ["github.com"])
    }

    @Test func historyCanBeTurnedOffAndCleared() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        try Config(browser: browser.path, defaultProfile: "Default", routes: []).save(to: fixture.configURL)
        let model = model(fixture)
        // Isolated configurations never write to the user's history.
        #expect(model.historyURL == fixture.root.appendingPathComponent("history.jsonl"))
        let link = try #require(URL(string: "https://example.com"))
        let destination = Destination(browser: browser.path, profile: "Default")
        model.recordLink(
            url: link, destination: destination, origin: .default, config: model.config, error: nil)
        #expect(try HistoryStore(url: model.historyURL).entries().count == 1)
        model.setHistoryEnabled(false)
        #expect(model.flush())
        #expect(try Config.load(from: fixture.configURL).history == HistorySettings(enabled: false))
        model.recordLink(
            url: link, destination: destination, origin: .default, config: model.config, error: nil)
        #expect(try HistoryStore(url: model.historyURL).entries().count == 1)
        model.clearHistory()
        #expect(model.historyError == nil)
        #expect(!FileManager.default.fileExists(atPath: model.historyURL.path))
        model.setHistoryEnabled(true)
        #expect(model.flush())
        #expect(try Config.load(from: fixture.configURL).history == nil)
    }

    @Test func changingDefaultBrowserClearsOnlyDestinationsThatInheritIt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser()
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        try fixture.profiles(["Default": "Chrome Work"])
        try fixture.profiles(["Default": "Ryan"], folder: "net.imput.helium")
        let rules = [Route(value: "inherited"), Route(value: "explicit", browser: helium.path)]
        try Config(browser: helium.path, defaultProfile: "Default", routes: rules).save(to: fixture.configURL)
        let model = model(fixture)
        model.selectDefaultBrowser(chrome.path)
        #expect(model.config.defaultProfile.isEmpty)
        #expect(model.config.routes[0].profile.isEmpty)
        #expect(model.config.routes[1].profile == "Default")
        #expect(!model.flush())
        #expect(try Config.load(from: fixture.configURL).browser == helium.path)
    }
}
