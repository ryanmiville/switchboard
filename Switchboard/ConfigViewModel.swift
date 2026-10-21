import Combine
import Foundation
import SwiftUI

@MainActor
final class ConfigViewModel: ObservableObject {
    @Published var config: Config {
        didSet {
            guard !isLoading else { return }
            if oldValue.browser != config.browser { refreshProfiles() }
            needsSave = true
            scheduleSave()
        }
    }
    @Published private(set) var availableProfiles: [Profile] = []
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

    func deleteRoute(_ route: Route) {
        config.routes.removeAll { $0.id == route.id }
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
        availableProfiles = []
        do {
            availableProfiles = try profileStore.profiles(browserPath: config.browser)
            let normalized = try profileStore.normalized(config)
            if normalized != config {
                let wasLoading = isLoading
                isLoading = true
                config = normalized
                isLoading = wasLoading
                needsSave = true
            }
            profileError = nil
        } catch {
            profileError = error.localizedDescription
        }
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
        do {
            let normalized = try profileStore.normalized(config)
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
