import Foundation

struct BrowserProfiles {
    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    // macOS user-data folders are browser-specific, not generally bundle identifiers.
    static let dataDirectories = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.microsoft.edgemac.Canary": "Microsoft Edge Canary",
        "com.opera.Opera": "com.operasoftware.Opera",
        "com.opera.OperaBeta": "com.operasoftware.OperaNext",
        "com.opera.OperaDeveloper": "com.operasoftware.OperaDeveloper",
        "com.operasoftware.Opera": "com.operasoftware.Opera",
        "com.operasoftware.OperaNext": "com.operasoftware.OperaNext",
        "com.operasoftware.OperaDeveloper": "com.operasoftware.OperaDeveloper",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.keksbay.Arc": "Arc/User Data",
        "company.thebrowser.Browser": "Arc/User Data",
        "net.imput.helium": "net.imput.helium",
    ]

    func profiles(browserPath: String) throws -> [Profile] {
        guard let id = Bundle(path: browserPath)?.bundleIdentifier,
            let directory = Self.dataDirectories[id]
        else {
            throw ProfileError.browserUnavailable
        }
        let state = homeDirectory.appendingPathComponent(
            "Library/Application Support/\(directory)/Local State")
        let data: Data
        do {
            data = try Data(contentsOf: state)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A newly installed browser may not have created its first profile yet.
            return [Profile(name: "Default", directory: "Default")]
        }
        let cache = try JSONDecoder().decode(LocalState.self, from: data).profile?.infoCache ?? [:]
        let profiles = cache.map { Profile(name: $0.value.name ?? $0.key, directory: $0.key) }
        if profiles.isEmpty { return [Profile(name: "Default", directory: "Default")] }
        return profiles.sorted {
            if ($0.directory == "Default") != ($1.directory == "Default") { return $0.directory == "Default" }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.directory < $1.directory : order == .orderedAscending
        }
    }

    static func directory(for selection: String, in profiles: [Profile]) throws -> String {
        // The documented directory format takes precedence over legacy display names.
        if profiles.contains(where: { $0.directory == selection }) { return selection }
        let matches = profiles.filter { $0.name == selection }
        guard matches.count == 1 else {
            throw matches.isEmpty ? ProfileError.missing(selection) : ProfileError.ambiguous(selection)
        }
        return matches[0].directory
    }

    func normalized(_ config: Config) throws -> Config {
        let profiles = try profiles(browserPath: config.browser)
        var normalized = config
        normalized.defaultProfile = try Self.directory(for: config.defaultProfile, in: profiles)
        for index in normalized.routes.indices {
            normalized.routes[index].profile = try Self.directory(
                for: config.routes[index].profile, in: profiles)
        }
        return normalized
    }

    private struct LocalState: Decodable {
        struct Cache: Decodable {
            struct Info: Decodable { let name: String? }
            let infoCache: [String: Info]?
            enum CodingKeys: String, CodingKey {
                case infoCache = "info_cache"
            }
        }
        let profile: Cache?
    }
}

enum ProfileError: LocalizedError {
    case browserUnavailable
    case missing(String)
    case ambiguous(String)

    var errorDescription: String? {
        switch self {
        case .browserUnavailable:
            "The selected browser is unavailable. Choose an installed browser in Switchboard."
        case .missing(let name):
            "The profile “\(name)” is unavailable. Choose an existing profile in Switchboard."
        case .ambiguous(let name):
            "Several profiles are named “\(name)”. Choose the intended profile in Switchboard."
        }
    }
}
