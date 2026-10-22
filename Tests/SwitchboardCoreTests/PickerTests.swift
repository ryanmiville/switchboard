import AppKit
import Carbon.HIToolbox
import Testing

@testable import SwitchboardCore

@MainActor
@Suite(.serialized)
struct PickerTests {
    private func installed(_ url: URL, name: String) -> InstalledBrowser {
        InstalledBrowser(url: url, name: name, icon: NSImage())
    }

    private func model(_ fixture: Fixture, browser: URL, routes: [Route] = []) throws -> TabPickerModel {
        try Config(browser: browser.path, defaultProfile: "Default", routes: routes).save(
            to: fixture.configURL)
        let viewModel = ConfigViewModel(
            configURL: fixture.configURL, profileStore: BrowserProfiles(homeDirectory: fixture.root),
            browsers: [], autosaveDelay: 3600)
        let model = TabPickerModel(viewModel: viewModel)
        model.catalog = PickerCatalog(profileStore: BrowserProfiles(homeDirectory: fixture.root))
        model.browsers = { [] }
        return model
    }

    private func selectionModel(_ fixture: Fixture) throws -> (TabPickerModel, URL, URL) {
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        let chrome = try fixture.browser(name: "Chrome")
        try fixture.profiles(["Default": "Ryan", "Profile 1": "Work"], folder: "net.imput.helium")
        try fixture.profiles(["Default": "Personal", "Profile 1": "Horizon 3"])
        let model = try model(fixture, browser: helium)
        let browsers = [installed(chrome, name: "Google Chrome.app"), installed(helium, name: "Helium.app")]
        model.browsers = { browsers }
        model.viewModel.config.picker = PickerSettings(favorites: [
            PickerFavorite(browser: helium.path, profile: "Default", name: "Ryan"),
            PickerFavorite(browser: chrome.path, profile: "Profile 1", name: "Horizon 3"),
        ])
        model.refresh()
        return (model, chrome, helium)
    }

    @Test func legacyPickerJSONKeepsAllDestinationsAndExplicitEmptySelectionRoundTrips() throws {
        let legacy = PickerSettings()
        let data = try JSONEncoder().encode(legacy)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["destinations"] == nil)
        let decoded = try JSONDecoder().decode(PickerSettings.self, from: data)
        let destination = Destination(browser: "/Applications/Helium.app", profile: "Default")
        #expect(decoded.destinations == nil)
        #expect(decoded.includes(destination))

        var selected = decoded
        selected.destinations = []
        let empty = try JSONDecoder().decode(PickerSettings.self, from: JSONEncoder().encode(selected))
        #expect(empty.destinations == [])
        #expect(!empty.includes(destination))
        selected.destinations = [destination]
        #expect(
            try JSONDecoder().decode(PickerSettings.self, from: JSONEncoder().encode(selected)) == selected)
    }

    @Test func hidingOneProfileUsesBrowserIdentityAndKeepsNewProfilesUnchecked() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let (model, chrome, helium) = try selectionModel(fixture)
        #expect(model.choices.count == 4)
        let hidden = try #require(
            model.allChoices.first {
                $0.destination == Destination(browser: chrome.path, profile: "Default")
            })
        model.setIncluded(false, for: hidden)
        #expect(!model.choices.contains { $0.id == hidden.id })
        #expect(model.choices.contains { $0.id == Destination(browser: helium.path, profile: "Default") })

        try fixture.profiles([
            "Default": "Renamed Personal", "Profile 1": "Horizon 3", "Profile 2": "New Work",
        ])
        model.refresh()
        #expect(model.allChoices.count == 5)
        #expect(model.choices.count == 3)
        #expect(!model.choices.contains { $0.destination.profile == "Profile 2" })
        #expect(!model.choices.contains { $0.id == hidden.id })
        let renamed = try #require(model.allChoices.first { $0.id == hidden.id })
        #expect(renamed.profileName == "Renamed Personal")
        model.setIncluded(true, for: renamed)
        #expect(model.choices.contains { $0.id == hidden.id })
        #expect(!model.choices.contains { $0.destination.profile == "Profile 2" })
        #expect(model.viewModel.flush())
        #expect(
            try Config.load(from: fixture.configURL).picker?.destinations
                == model.viewModel.config.picker?.destinations)
    }

    @Test func favoritesOnlyPreservesRoutingAndHiddenFavoritesGetNoShortcutOrLaunch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let (model, chrome, helium) = try selectionModel(fixture)
        let rule = Route(condition: .domain, value: "example.com", profile: "Profile 1", browser: chrome.path)
        model.viewModel.config.routes = [rule]
        model.showOnlyFavorites()
        #expect(
            model.choices.map(\.id) == [
                Destination(browser: helium.path, profile: "Default"),
                Destination(browser: chrome.path, profile: "Profile 1"),
            ])
        let hiddenFavorite = try #require(model.choices.first)
        model.setIncluded(false, for: hiddenFavorite)
        #expect(model.favoriteNumber(for: hiddenFavorite) == nil)
        #expect(model.favoriteNumber(for: try #require(model.choices.first)) == 1)
        #expect(model.viewModel.config.picker?.favorites.count == 2)
        model.urlString = "https://example.com/path"
        model.launch = { _, _ in Issue.record("A hidden destination was launched") }
        #expect(!model.open(hiddenFavorite))
        #expect(model.error?.contains("hidden") == true)
        #expect(model.viewModel.flush())
        let saved = try Config.load(from: fixture.configURL)
        #expect(saved.browser == helium.path)
        #expect(saved.defaultProfile == "Default")
        #expect(saved.routes.count == 1)
        let savedRule = try #require(saved.routes.first)
        #expect(savedRule.condition == rule.condition)
        #expect(savedRule.value == rule.value)
        #expect(savedRule.browser == rule.browser)
        #expect(savedRule.profile == rule.profile)
    }

    @Test func emptySelectionStaysEmptyAndShowAllRestoresDiscovery() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let (model, _, _) = try selectionModel(fixture)
        model.showOnlyFavorites()
        for choice in model.choices { model.setIncluded(false, for: choice) }
        #expect(model.choices.isEmpty)
        #expect(model.allChoices.count == 4)
        #expect(model.viewModel.config.picker?.destinations == [])
        #expect(model.viewModel.flush())
        #expect(try Config.load(from: fixture.configURL).picker?.destinations == [])
        model.refresh()
        #expect(model.choices.isEmpty)
        model.showAllDestinations()
        #expect(model.choices.count == 4)
        #expect(model.viewModel.config.picker?.destinations == nil)
    }

    @Test func missingSelectedProfileRemainsVisibleWithoutSubstitutingAnotherBrowser() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let (model, chrome, helium) = try selectionModel(fixture)
        let selected = Destination(browser: chrome.path, profile: "Default")
        model.viewModel.config.picker?.destinations = [selected]
        try fixture.profiles(["Profile 1": "Horizon 3"])
        model.refresh()
        let missing = try #require(model.choices.first)
        #expect(model.choices.count == 1)
        #expect(missing.id == selected)
        #expect(missing.error != nil)
        #expect(model.allChoices.contains { $0.id == Destination(browser: helium.path, profile: "Default") })
        model.urlString = "https://example.com"
        model.launch = { _, _ in Issue.record("An unavailable selected profile was launched") }
        #expect(!model.open(missing))
        #expect(model.urlString == "https://example.com")
        model.setIncluded(false, for: missing)
        #expect(model.choices.isEmpty)
        #expect(!model.allChoices.contains { $0.id == selected })
    }

    @Test func unavailableSelectedBrowserIsRetainedAndUnselectedDiscoveryErrorsStayHidden() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let (model, chrome, helium) = try selectionModel(fixture)
        let selected = Destination(browser: helium.path, profile: "Profile 1")
        model.viewModel.config.picker?.destinations = [selected]
        model.browsers = { [self.installed(chrome, name: "Chrome")] }
        try Data("broken".utf8).write(
            to: fixture.root.appendingPathComponent("Library/Application Support/Google/Chrome/Local State"))
        model.refresh()
        #expect(model.choices.count == 1)
        #expect(model.choices.first?.id == selected)
        #expect(model.choices.first?.error != nil)
        #expect(model.allChoices.contains { $0.destination.browser == chrome.path && $0.error != nil })
    }

    @Test func pickerLabelsOmitAppExtensionAndHiddenProfilesCannotBeNewFavorites() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let (model, chrome, _) = try selectionModel(fixture)
        let personal = try #require(
            model.allChoices.first {
                $0.id == Destination(browser: chrome.path, profile: "Default")
            })
        #expect(personal.browserDisplayName == "Google Chrome")
        #expect(personal.label == "Google Chrome · Personal")
        model.showOnlyFavorites()
        model.toggleFavorite(personal)
        #expect(model.viewModel.config.picker?.favorites.count == 2)
        model.setIncluded(true, for: personal)
        model.toggleFavorite(personal)
        #expect(model.choices.filter(\.isFavorite).count == 3)
        #expect(model.favoriteNumber(for: personal) == 3)
    }

    @Test func favoritesResolveOnceAndPersistBrowserSpecificDirectories() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        let chrome = try fixture.browser(name: "Chrome")
        try fixture.profiles(["Default": "Ryan", "Profile 1": "Work"], folder: "net.imput.helium")
        try fixture.profiles(["Default": "Your Chrome", "Profile 1": "horizon3.ai"])
        let settings = PickerSettings.initial(
            browsers: [installed(chrome, name: "Chrome"), installed(helium, name: "Helium")],
            profileStore: BrowserProfiles(homeDirectory: fixture.root))
        #expect(settings.favorites.map(\.name) == ["Ryan", "Horizon 3"])
        #expect(settings.favorites.map(\.profile) == ["Default", "Profile 1"])
        #expect(settings.favorites.map(\.browser) == [helium.path, chrome.path])
        var config = Config(browser: helium.path, defaultProfile: "Default", routes: [])
        config.picker = settings
        try config.save(to: fixture.configURL)
        #expect(try Config.load(from: fixture.configURL).picker == settings)

        // Renaming a profile doesn't redirect a saved favorite to another directory.
        try fixture.profiles(["Default": "horizon3.ai", "Profile 1": "Renamed"])
        let choices = PickerCatalog(profileStore: BrowserProfiles(homeDirectory: fixture.root)).choices(
            browsers: [installed(chrome, name: "Chrome"), installed(helium, name: "Helium")],
            favorites: settings.favorites)
        #expect(choices.prefix(2).map(\.profileName) == ["Ryan", "Horizon 3"])
        #expect(choices[1].destination == Destination(browser: chrome.path, profile: "Profile 1"))
        #expect(choices[1].error == nil)
    }

    @Test func ambiguousInitialFavoriteIsNotGuessed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser()
        try fixture.profiles(["Default": "horizon3.ai", "Profile 1": "horizon3.ai"])
        let settings = PickerSettings.initial(
            browsers: [installed(chrome, name: "Chrome")],
            profileStore: BrowserProfiles(homeDirectory: fixture.root))
        #expect(settings.favorites.isEmpty)
    }

    @Test func unavailableFavoriteDoesNotResolveByDisplayNameOrAnotherBrowser() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser(name: "Chrome")
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        try fixture.profiles(["Default": "Horizon 3"])
        try fixture.profiles(["Profile 1": "Horizon 3"], folder: "net.imput.helium")
        let favorite = PickerFavorite(browser: chrome.path, profile: "Profile 1", name: "Horizon 3")
        let choices = PickerCatalog(profileStore: BrowserProfiles(homeDirectory: fixture.root)).choices(
            browsers: [installed(chrome, name: "Chrome"), installed(helium, name: "Helium")],
            favorites: [favorite, favorite])
        #expect(choices.filter(\.isFavorite).count == 1)
        #expect(choices[0].destination == favorite.destination)
        #expect(choices[0].error != nil)
        #expect(choices.contains { $0.destination.browser == helium.path && $0.error == nil })
    }

    @Test func unreadableProfilesRemainVisible() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser()
        try fixture.profiles([:])
        try Data("broken".utf8).write(
            to: fixture.root.appendingPathComponent("Library/Application Support/Google/Chrome/Local State"))
        let choices = PickerCatalog(profileStore: BrowserProfiles(homeDirectory: fixture.root)).choices(
            browsers: [installed(chrome, name: "Chrome")], favorites: [])
        #expect(choices.count == 1)
        #expect(choices.first?.error != nil)
    }

    @Test func manualChoiceBypassesRulesAndFlushesEditsBeforeLaunching() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        let chrome = try fixture.browser(name: "Chrome")
        try fixture.profiles(["Default": "Ryan", "Profile 1": "Work"], folder: "net.imput.helium")
        try fixture.profiles(["Default": "Your Chrome", "Profile 1": "horizon3.ai"])
        let model = try model(fixture, browser: helium, routes: [Route(value: "example.com")])
        model.viewModel.config.routes[0].value = "edited.example.com"
        let launcher = BrowserLauncher(
            profileStore: BrowserProfiles(homeDirectory: fixture.root),
            runProcess: { executable, arguments in
                #expect(
                    executable.standardizedFileURL.path
                        == chrome.appendingPathComponent("Contents/MacOS/ActualBrowser").path)
                #expect(
                    arguments == [
                        "--profile-directory=Profile 1", "https://example.com/Case?a=b%20c#fragment",
                    ])
                let saved = try Config.load(from: fixture.configURL)
                #expect(saved.routes[0].value == "edited.example.com")
            })
        model.launch = { try launcher.launch(url: $0, destination: $1) }
        model.urlString = "https://example.com/Case?a=b%20c#fragment"
        #expect(
            model.open(
                PickerChoice(
                    destination: Destination(browser: chrome.path, profile: "Profile 1"),
                    browserName: "Chrome", profileName: "Horizon 3", isFavorite: true)))
        #expect(!model.viewModel.hasUnsavedChanges)
    }

    @Test func failedSaveRetainsEditsAndPreventsManualLaunch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        let model = try model(fixture, browser: browser)
        model.viewModel.config.routes.append(Route(value: "pending"))
        try FileManager.default.removeItem(at: fixture.configURL)
        try FileManager.default.createDirectory(at: fixture.configURL, withIntermediateDirectories: false)
        model.urlString = "https://example.com"
        model.launch = { _, _ in Issue.record("Launched with unsaved edits") }
        #expect(
            !model.open(
                PickerChoice(
                    destination: Destination(browser: browser.path, profile: "Default"),
                    browserName: "Chrome", profileName: "Ryan", isFavorite: true)))
        #expect(model.viewModel.hasUnsavedChanges)
        #expect(model.viewModel.config.routes.first?.value == "pending")
        #expect(model.error != nil)
    }

    @Test func failedLaunchPreservesURLForRetryAndDoesNotFallBack() throws {
        struct Failure: LocalizedError { var errorDescription: String? { "Test launch failed" } }
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        let model = try model(fixture, browser: browser)
        model.urlString = "https://example.com/?a=1#part"
        var attempts = 0
        model.launch = { _, _ in
            attempts += 1
            throw Failure()
        }
        let choice = PickerChoice(
            destination: Destination(browser: browser.path, profile: "Default"),
            browserName: "Chrome", profileName: "Ryan", isFavorite: true)
        #expect(!model.open(choice))
        #expect(attempts == 1)
        #expect(model.urlString == "https://example.com/?a=1#part")
        #expect(model.error?.contains("Test launch failed") == true)
        model.launch = { _, _ in attempts += 1 }
        #expect(model.open(choice))
        #expect(attempts == 2)
        #expect(model.error == nil)
    }

    @Test func failedCaptureClearsPreviousURLAndOffersPasteFallback() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        let model = try model(fixture, browser: browser)
        model.reader = CurrentTabReader(execute: { _ in tabReply("https://example.com/first") })
        model.prepare(source: CurrentTabSource(bundleIdentifier: "net.imput.helium", processIdentifier: 101))
        #expect(model.urlString == "https://example.com/first")
        model.reader = CurrentTabReader(execute: { _ in throw CurrentTabError.automationDenied })
        model.prepare(source: CurrentTabSource(bundleIdentifier: "com.google.Chrome", processIdentifier: 101))
        #expect(model.urlString.isEmpty)
        #expect(model.needsAutomationPermission)
        #expect(model.error?.contains("Automation") == true)
    }

    @Test func captureRejectsUnsupportedApplicationsBeforeSendingEvents() {
        let reader = CurrentTabReader(execute: { _ in
            Issue.record("Sent Apple events to an unsupported application")
            return tabReply("https://example.com")
        })
        #expect(throws: CurrentTabError.unsupportedBrowser) {
            try reader.read(
                source: CurrentTabSource(bundleIdentifier: "com.apple.finder", processIdentifier: 101))
        }
        #expect(throws: CurrentTabError.unsupportedBrowser) { try reader.read(source: nil) }
    }

    @Test func choosingFavoriteAfterPermissionFailureKeepsTheRecoveryMessage() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        let model = try model(fixture, browser: browser)
        model.reader = CurrentTabReader(execute: { _ in throw CurrentTabError.automationDenied })
        model.prepare(source: CurrentTabSource(bundleIdentifier: "com.google.Chrome", processIdentifier: 101))
        let captureError = try #require(model.error)
        let choice = PickerChoice(
            destination: Destination(browser: browser.path, profile: "Default"),
            browserName: "Chrome", profileName: "Work", isFavorite: true)
        model.launch = { _, _ in Issue.record("No URL was captured") }

        #expect(!model.open(choice))
        #expect(model.error == captureError)
        #expect(model.needsAutomationPermission)

        model.urlString = "file:///tmp/not-a-web-link"
        #expect(!model.open(choice))
        #expect(!model.needsAutomationPermission)
        #expect(model.error?.contains("complete HTTP or HTTPS") == true)

        model.urlString = "https://example.com/pasted"
        model.launch = { url, destination in
            #expect(url.absoluteString == "https://example.com/pasted")
            #expect(destination == choice.destination)
        }
        #expect(model.open(choice))
        #expect(!model.needsAutomationPermission)
        #expect(model.error == nil)
    }

    @Test(arguments: ["chrome://settings", "file:///tmp/test", "javascript:alert(1)", "https:relative"])
    func captureRejectsNonWebPages(_ value: String) {
        let reader = CurrentTabReader(execute: { _ in tabReply(value) })
        #expect(throws: CurrentTabError.nonWebURL) {
            try reader.read(
                source: CurrentTabSource(bundleIdentifier: "com.google.Chrome", processIdentifier: 101))
        }
    }

    @Test func noTabIsDistinctFromAnInvalidURL() {
        let reader = CurrentTabReader(execute: { _ in tabReply("") })
        #expect(throws: CurrentTabError.noTab) {
            try reader.read(
                source: CurrentTabSource(bundleIdentifier: "net.imput.helium", processIdentifier: 101))
        }
    }

    @Test func shortcutRequiresAnIntentionalModifier() {
        #expect(KeyboardShortcut.default.isValid)
        #expect(KeyboardShortcut.default.label == "⌃⌥Space")
        #expect(!KeyboardShortcut(keyCode: 49, modifiers: 0, key: "Space").isValid)
        #expect(!KeyboardShortcut(keyCode: 49, modifiers: UInt32(shiftKey), key: "Space").isValid)
    }

    @Test func leavingTheRecorderWindowRestoresShortcutHandling() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let button = ShortcutButton()
        window.contentView = button
        var recording: [Bool] = []
        button.onRecordingChanged = { recording.append($0) }
        button.beginRecording()
        #expect(button.recording)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(!button.recording)
        #expect(recording == [true, false])
    }
}
