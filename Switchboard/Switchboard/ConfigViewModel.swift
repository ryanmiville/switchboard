import Foundation
import Combine

@MainActor
final class ConfigViewModel: ObservableObject {
    @Published var config: Config
    @Published var availableProfiles: [String] = []
    @Published var saveError: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.config = Config.loadOrDefault()
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
        let defaultProfile = availableProfiles.first ?? config.defaultProfile
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
    static func discoverProfiles(browserPath: String) -> [String] {
        guard let bundleId = Bundle(path: browserPath)?.bundleIdentifier else {
            return ["Default"]
        }
        
        let localStateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(bundleId)/Local State")
        
        guard let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return ["Default"]
        }
        
        let profiles = Array(infoCache.keys)
        
        // Sort: Default first, then Profile 1, Profile 2, etc.
        return profiles.sorted { lhs, rhs in
            if lhs == "Default" { return true }
            if rhs == "Default" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
}
