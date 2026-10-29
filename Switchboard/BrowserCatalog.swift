import Foundation

// A supported Chromium browser bundle, read without AppKit so the CLI can share it.
struct BrowserInfo: Equatable {
    let path: String
    let name: String
    let bundleIdentifier: String
    // Other names the bundle declares, such as Google Chrome's "Chrome".
    let alternateNames: [String]

    init?(path: String) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
            BrowserProfiles.dataDirectories[id] != nil
        else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let info = bundle.infoDictionary ?? [:]
        self.path = url.path
        self.name = name
        bundleIdentifier = id
        alternateNames = ["CFBundleDisplayName", "CFBundleName"].compactMap { info[$0] as? String }
            .filter { $0 != name }
    }

    static func displayName(path: String) -> String {
        BrowserInfo(path: path)?.name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

// The app lists browsers through Launch Services, which needs AppKit. The CLI scans the usual application
// folders instead, and also accepts any supported browser the configuration already names.
struct BrowserCatalog {
    var profileStore: BrowserProfiles
    var applicationDirectories: [URL]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationDirectories: [URL]? = nil
    ) {
        profileStore = BrowserProfiles(homeDirectory: homeDirectory)
        self.applicationDirectories =
            applicationDirectories ?? [
                URL(fileURLWithPath: "/Applications"), homeDirectory.appendingPathComponent("Applications"),
            ]
    }

    func browsers(including paths: [String] = []) -> [BrowserInfo] {
        var found: [String: BrowserInfo] = [:]
        for directory in applicationDirectories {
            let contents =
                (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
                ?? []
            for url in contents where url.pathExtension == "app" {
                if let info = BrowserInfo(path: url.path) { found[info.path] = info }
            }
        }
        for path in paths {
            if let info = BrowserInfo(path: path) { found[info.path] = info }
        }
        return found.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }
}
