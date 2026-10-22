import Combine
import Foundation
import SwiftUI

@MainActor
final class ConfigViewModel: ObservableObject {
    @Published var config: Config {
        didSet {
            guard !isLoading else { return }
            if oldValue.browserPaths != config.browserPaths { refreshProfiles() }
            needsSave = true
            scheduleSave()
        }
    }
    @Published private(set) var profilesByBrowser: [String: [Profile]] = [:]
    @Published private(set) var availableBrowsers: [InstalledBrowser]
    @Published private(set) var loadError: String?
    @Published private(set) var saveError: String?
    @Published private(set) var profileError: String?

    let configURL: URL
    private let profileStore: BrowserProfiles
    private let autosaveDelay: TimeInterval
    private var pendingSave: DispatchWorkItem?
    private var isLoading = false
    private var needsSave = false

    var hasUnsavedChanges: Bool { needsSave && loadError == nil }
    var availableProfiles: [Profile] { profiles(for: config.browser) }

    func profiles(for browser: String) -> [Profile] { profilesByBrowser[browser] ?? [] }

    init(
        configURL: URL = Config.configPath,
        profileStore: BrowserProfiles = BrowserProfiles(),
        browsers: [InstalledBrowser]? = nil,
        autosaveDelay: TimeInterval = 0.5
    ) {
        self.configURL = configURL
        self.profileStore = profileStore
        self.autosaveDelay = autosaveDelay
        config = .defaults
        availableBrowsers = browsers ?? BrowserDiscovery.chromiumBrowsers()
        reload()
    }

    func addRoute() {
        config.routes.append(Route(profile: config.defaultProfile))
    }

    // Sheets edit a value copy. Only Done changes the live configuration or starts autosave.
    @discardableResult
    func commitRoute(_ draft: RouteDraft) -> Bool {
        guard loadError == nil else { return false }
        if draft.isNew {
            guard !config.routes.contains(where: { $0.id == draft.id }) else { return false }
            config.routes.append(draft.route)
        } else {
            guard let index = config.routes.firstIndex(where: { $0.id == draft.id }) else { return false }
            config.routes[index] = draft.route
        }
        return true
    }

    func discoverProfiles(for browser: String) throws -> [Profile] {
        try profileStore.profiles(browserPath: browser)
    }

    func selectDefaultBrowser(_ browser: String) {
        guard browser != config.browser else { return }
        var updated = config
        updated.browser = browser
        updated.defaultProfile = ""
        for index in updated.routes.indices where updated.routes[index].browser == nil {
            updated.routes[index].profile = ""
        }
        config = updated
    }

    func initializePicker() {
        guard config.picker == nil, loadError == nil else { return }
        config.picker = PickerSettings.initial(browsers: availableBrowsers, profileStore: profileStore)
    }

    func setPickerShortcut(_ shortcut: KeyboardShortcut) {
        guard shortcut.isValid else { return }
        var settings = config.picker ?? PickerSettings()
        settings.shortcut = shortcut
        config.picker = settings
    }

    func toggleFavorite(_ choice: PickerChoice) {
        var settings = config.picker ?? PickerSettings()
        if settings.favorites.contains(where: { $0.id == choice.id }) {
            settings.favorites.removeAll { $0.id == choice.id }
        } else if choice.error == nil {
            settings.favorites.append(
                PickerFavorite(
                    browser: choice.destination.browser, profile: choice.destination.profile,
                    name: choice.profileName))
        }
        config.picker = settings
    }

    func deleteRoute(_ route: Route) {
        config.routes.removeAll { $0.id == route.id }
    }

    func selectBrowser(_ browser: String?, for route: Route) {
        guard let index = config.routes.firstIndex(where: { $0.id == route.id }) else { return }
        var updated = config.routes[index]
        if (updated.browser ?? config.browser) != (browser ?? config.browser) {
            // Directory names are only meaningful within one browser. Require a new choice.
            updated.profile = ""
        }
        updated.browser = browser
        config.routes[index] = updated
    }

    // Text fields can finish editing after their row was deleted or moved.
    // Resolve by identity on every access instead of retaining an array index.
    func binding(for route: Route) -> Binding<Route> {
        Binding(
            get: { self.config.routes.first(where: { $0.id == route.id }) ?? route },
            set: { updated in
                guard let index = self.config.routes.firstIndex(where: { $0.id == route.id }) else { return }
                self.config.routes[index] = updated
            }
        )
    }

    func moveRoute(_ route: Route, by offset: Int) {
        guard let index = config.routes.firstIndex(where: { $0.id == route.id }),
            config.routes.indices.contains(index + offset)
        else { return }
        config.routes.swapAt(index, index + offset)
    }

    func moveRoute(id: UUID, toInsertionIndex insertion: Int) {
        guard let source = config.routes.firstIndex(where: { $0.id == id }),
            (0...config.routes.count).contains(insertion)
        else { return }
        let destination = insertion > source ? insertion - 1 : insertion
        guard source != destination else { return }
        var routes = config.routes
        let route = routes.remove(at: source)
        routes.insert(route, at: destination)
        config.routes = routes
    }

    func reload() {
        pendingSave?.cancel()
        isLoading = true
        defer {
            isLoading = false
            if needsSave { scheduleSave() }
        }
        do {
            config = try Config.loadOrDefault(from: configURL)
            loadError = nil
            saveError = nil
            needsSave = false
            refreshProfiles()
        } catch {
            loadError =
                "Your settings couldn’t be read. The file has been left unchanged. Open it to repair it, then retry. \(error.localizedDescription)"
            needsSave = false
        }
    }

    func refreshProfiles() {
        var discovered: [String: [Profile]] = [:]
        var errors: [String] = []
        for browser in config.browserPaths.sorted() {
            do {
                discovered[browser] = try profileStore.profiles(browserPath: browser)
            } catch {
                errors.append("\((browser as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }
        profilesByBrowser = discovered
        if errors.isEmpty {
            do {
                let normalized = try profileStore.normalized(config)
                if normalized != config {
                    let wasLoading = isLoading
                    isLoading = true
                    config = normalized
                    isLoading = wasLoading
                    needsSave = true
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        profileError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        if needsSave && !isLoading { scheduleSave() }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        guard loadError == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: work)
    }

    // Used by shutdown and before routing from an open editor; never wait for debounce there.
    @discardableResult
    func flush() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard loadError == nil else { return false }
        guard needsSave else { return true }
        let normalized: Config
        do {
            normalized = try profileStore.normalized(config)
        } catch {
            profileError = error.localizedDescription
            return false
        }
        do {
            try normalized.save(to: configURL)
            isLoading = true
            config = normalized
            isLoading = false
            needsSave = false
            saveError = nil
            profileError = nil
            return true
        } catch {
            saveError =
                "Your changes couldn’t be saved. They are still in this window. \(error.localizedDescription) Fix the issue and retry saving."
            return false
        }
    }
}

struct RouteDraft: Identifiable {
    var route: Route
    let isNew: Bool
    var id: UUID { route.id }

    init(config: Config, route: Route? = nil) {
        self.route = route ?? Route(condition: .domain, profile: config.defaultProfile)
        isNew = route == nil
    }

    mutating func selectBrowser(_ browser: String?, defaultBrowser: String) {
        if (route.browser ?? defaultBrowser) != (browser ?? defaultBrowser) {
            route.profile = ""
        }
        route.browser = browser
    }
}
