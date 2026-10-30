import AppKit
import ServiceManagement
import SwiftUI
import Testing

@testable import SwitchboardCore

// Golden images of the settings window, one per pane and appearance. Snapshot.swift explains recording.
@MainActor
@Suite(.serialized)
struct SnapshotTests {
    // The settings window's default size in SwitchboardApp.
    private let size = CGSize(width: 880, height: 700)

    @Test(arguments: ["general", "routing", "quickSwitch"], [false, true])
    func settingsPane(pane: String, dark: Bool) async throws {
        let settings = try SettingsFixture()
        defer { settings.cleanUp() }
        let pixels = try await Snapshot.render(settings.view(pane: pane), size: size, dark: dark)
        try Snapshot.check("settings-\(pane)-\(dark ? "dark" : "light")", pixels)
    }
}

// Two fixture browsers with two profiles each, three rules and two Quick Switch favorites. Nothing reads the
// installed browsers, ~/.config or the app's saved pane, so the images show no personal data.
@MainActor
private struct SettingsFixture {
    let fixture: Fixture
    let viewModel: ConfigViewModel
    let picker: TabPickerController
    let loginItem: LoginItemController
    let defaultsSuite = "switchboard-snapshots-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        fixture = try Fixture()
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium")
        let chrome = try fixture.browser(name: "Google Chrome")
        try fixture.profiles(
            ["Default": "Personal", "Profile 1": "Side Project"], folder: "net.imput.helium")
        try fixture.profiles(["Default": "Work", "Profile 1": "Client"])
        try Config(
            browser: helium.path, defaultProfile: "Default",
            routes: [
                Route(condition: .domain, value: "gitlab.com", profile: "Default", browser: chrome.path),
                Route(
                    condition: .contains, value: "github.com/acme", profile: "Profile 1", browser: chrome.path
                ),
                Route(condition: .exact, value: "https://calendar.example.com/", profile: "Profile 1"),
            ],
            picker: PickerSettings(favorites: [
                PickerFavorite(browser: helium.path, profile: "Default", name: "Personal"),
                PickerFavorite(browser: chrome.path, profile: "Default", name: "Work"),
            ])
        ).save(to: fixture.configURL)

        let profiles = BrowserProfiles(homeDirectory: fixture.root)
        let browsers = [chrome, helium].map {
            InstalledBrowser(
                url: $0, name: $0.lastPathComponent, icon: NSWorkspace.shared.icon(forFile: $0.path))
        }
        viewModel = ConfigViewModel(
            configURL: fixture.configURL, profileStore: profiles, browsers: browsers, autosaveDelay: 3600)
        picker = TabPickerController(viewModel: viewModel)
        picker.model.catalog = PickerCatalog(profileStore: profiles)
        picker.model.browsers = { browsers }
        picker.model.refresh()
        loginItem = LoginItemController(
            service: LoginItemService(
                status: { .notRegistered }, register: {}, unregister: {}, openSettings: {}))
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            throw SnapshotError("Couldn’t create the \(defaultsSuite) defaults suite.")
        }
        self.defaults = defaults
    }

    // ContentView reads its pane from @AppStorage, so each scene gives it a throwaway store.
    func view(pane: String) -> some View {
        defaults.set(pane, forKey: "settingsPane")
        return ContentView(viewModel: viewModel, picker: picker, loginItem: loginItem, onOpen: { _ in })
            .defaultAppStorage(defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: defaultsSuite)
        fixture.cleanUp()
    }
}
