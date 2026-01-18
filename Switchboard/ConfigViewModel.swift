import Foundation
import Combine

@MainActor
final class ConfigViewModel: ObservableObject {
    @Published var config: Config
    @Published var availableProfiles: [Profile] = []
    @Published var availableBrowsers: [InstalledBrowser] = []
    @Published var saveError: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.config = Config.loadOrDefault()
        self.availableBrowsers = BrowserDiscovery.chromiumBrowsers()
        self.availableProfiles = Self.discoverProfiles(browserPath: config.browser)
        
        // Auto-save on changes (debounced)
        $config
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] config in
                self?.save()
            }
            .store(in: &cancellables)
        
        // Update profiles when browser changes
        $config
            .map(\.browser)
            .removeDuplicates()
            .sink { [weak self] browserPath in
                self?.availableProfiles = Self.discoverProfiles(browserPath: browserPath)
            }
            .store(in: &cancellables)
    }
    
    func addRoute() {
        let defaultProfile = availableProfiles.first?.name ?? config.defaultProfile
        config.routes.append(Route(profile: defaultProfile))
    }
    
    func deleteRoute(at offsets: IndexSet) {
        config.routes.remove(atOffsets: offsets)
    }
    
    func deleteRoute(_ route: Route) {
        config.routes.removeAll { $0.id == route.id }
    }
    
    func moveRoute(from source: IndexSet, to destination: Int) {
        config.routes.move(fromOffsets: source, toOffset: destination)
    }
    
    func reload() {
        config = Config.loadOrDefault()
        availableProfiles = Self.discoverProfiles(browserPath: config.browser)
    }
    
    private func save() {
        do {
            try config.save()
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
    
    /// Discovers Chromium profiles from the browser's Local State file
    static func discoverProfiles(browserPath: String) -> [Profile] {
        guard let infoCache = Self.loadProfileInfoCache(browserPath: browserPath) else {
            return [Profile(name: "Default", directory: "Default")]
        }
        
        var profiles: [Profile] = []
        for (directory, info) in infoCache {
            guard let profileInfo = info as? [String: Any],
                  let name = profileInfo["name"] as? String else { continue }
            profiles.append(Profile(name: name, directory: directory))
        }
        
        // Sort: Default directory first, then by name
        return profiles.sorted { lhs, rhs in
            if lhs.directory == "Default" { return true }
            if rhs.directory == "Default" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    
    /// Resolves a profile display name to its directory identifier
    static func profileDirectory(forName name: String, browserPath: String) -> String {
        guard let infoCache = loadProfileInfoCache(browserPath: browserPath) else {
            return name // Fallback: assume name is directory
        }
        
        for (directory, info) in infoCache {
            guard let profileInfo = info as? [String: Any],
                  let profileName = profileInfo["name"] as? String else { continue }
            if profileName == name {
                return directory
            }
        }
        
        return name // Fallback: assume name is directory
    }
    
    private static func loadProfileInfoCache(browserPath: String) -> [String: Any]? {
        guard let bundleId = Bundle(path: browserPath)?.bundleIdentifier else {
            return nil
        }
        
        let localStateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(bundleId)/Local State")
        
        guard let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return nil
        }
        
        return infoCache
    }
}
