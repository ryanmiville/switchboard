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
        #expect(model.saveError != nil)
        #expect(model.config.defaultProfile == "Missing")
        #expect(try Data(contentsOf: fixture.configURL) == original)
        model.config.defaultProfile = "Default"
        #expect(model.flush())
        #expect(model.saveError == nil)
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
}
