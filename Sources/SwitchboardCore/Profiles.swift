import Foundation

// Chromium profiles, read from a browser's Local State. Profiles are saved by directory identifier
// (`Default`, `Profile 1`); display names are for people. Identical directory names in two
// browsers can belong to different people, so a profile is always resolved within one browser.

public struct Profile: Hashable, Sendable {
    /// The directory identifier, such as `Profile 1`.
    public var directory: String
    /// The display name, such as `Work`.
    public var name: String

    public init(directory: String, name: String) {
        self.directory = directory
        self.name = name
    }
}

public enum ProfileError: Error, Equatable, CustomStringConvertible {
    /// No profile was chosen.
    case selectionRequired
    /// The browser isn't installed, or isn't a supported Chromium browser.
    case browserUnavailable(String)
    /// Local State exists but couldn't be read or parsed.
    case unreadable(String)
    case missing(String)
    case ambiguous(String)

    public var description: String {
        switch self {
        case .selectionRequired: "Choose a profile for every rule and for the default browser."
        case .browserUnavailable(let locator) where locator.isEmpty:
            "No default browser is chosen. Choose one in \(Identity.appName)."
        case .browserUnavailable(let locator):
            "The browser at \(locator) is unavailable. Choose an installed browser."
        case .unreadable(let why): "The browser’s profiles couldn’t be read. \(why)"
        case .missing(let name): "The profile “\(name)” is unavailable. Choose an existing profile."
        case .ambiguous(let name): "Several profiles are named “\(name)”. Choose the intended profile."
        }
    }
}

/// What a Chromium browser last recorded about which of its profiles are in use.
public struct ProfileActivity: Equatable, Sendable {
    /// Directory identifiers of the profiles with windows open.
    public var open: [String]
    /// The directory identifier of the profile used last.
    public var lastUsed: String?

    public init(open: [String] = [], lastUsed: String? = nil) {
        self.open = open
        self.lastUsed = lastUsed
    }
}

public enum Profiles {
    /// The profiles in `browser`'s Local State, `Default` first, then by name. A browser that
    /// hasn't written Local State yet has just `Default`.
    public static func read(_ browser: BrowserInfo) throws(ProfileError) -> [Profile] {
        let url = browser.userData.appendingPathComponent("Local State")
        let fallback = [Profile(directory: "Default", name: "Default")]
        let data: Data
        do {
            guard let contents = try Files.contents(of: url) else { return fallback }
            data = contents
        } catch {
            throw .unreadable(error.message)
        }
        let cache: [String: Any]
        do {
            guard let state = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProfileError.unreadable("\(url.path): it isn’t a JSON object.")
            }
            cache = ((state["profile"] as? [String: Any])?["info_cache"] as? [String: Any]) ?? [:]
        } catch let error as ProfileError {
            throw error
        } catch {
            throw .unreadable("\(url.path): it isn’t valid JSON.")
        }
        let profiles = cache.map { directory, info in
            Profile(directory: directory, name: ((info as? [String: Any])?["name"] as? String) ?? directory)
        }
        if profiles.isEmpty { return fallback }
        return profiles.sorted { a, b in
            if (a.directory == "Default") != (b.directory == "Default") { return a.directory == "Default" }
            let (x, y) = (Array(a.name.lowercased().utf8), Array(b.name.lowercased().utf8))
            if x != y { return x.lexicographicallyPrecedes(y) }
            return Array(a.directory.utf8).lexicographicallyPrecedes(Array(b.directory.utf8))
        }
    }

    /// Which of `browser`'s profiles have windows open and which was used last, as Chromium records
    /// them in Local State (`profile.last_active_profiles`, `profile.last_used`). Chromium saves the
    /// file a few seconds after a change, so this can lag a profile switch. Best effort: anything
    /// unreadable is just unknown.
    public static func activity(_ browser: BrowserInfo) -> ProfileActivity {
        let url = browser.userData.appendingPathComponent("Local State")
        guard let data = try? Files.contents(of: url),
            let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = state["profile"] as? [String: Any]
        else { return ProfileActivity() }
        return ProfileActivity(
            open: profile["last_active_profiles"] as? [String] ?? [],
            lastUsed: profile["last_used"] as? String)
    }

    /// The profiles of the browser at `locator`.
    public static func of(_ browsers: Browsers, _ locator: String) throws(ProfileError) -> [Profile] {
        guard let info = browsers.at(locator) else { throw .browserUnavailable(locator) }
        return try read(info)
    }

    /// The directory a saved profile names: a directory identifier first, then a display name that
    /// only one profile has (older files saved display names).
    public static func directory(_ selection: String, in profiles: [Profile]) throws(ProfileError) -> String {
        if selection.isEmpty { throw .selectionRequired }
        if profiles.contains(where: { $0.directory == selection }) { return selection }
        let named = profiles.filter { $0.name == selection }
        switch named.count {
        case 1: return named[0].directory
        case 0: throw .missing(selection)
        default: throw .ambiguous(selection)
        }
    }

    /// `config` with every profile saved as its directory identifier, each resolved in its own
    /// destination's browser.
    public static func normalized(_ config: Config, _ browsers: Browsers) throws(ProfileError) -> Config {
        var cache: [String: [Profile]] = [:]
        func resolve(_ browser: String, _ selection: String) throws(ProfileError) -> String {
            if cache[browser] == nil { cache[browser] = try of(browsers, browser) }
            return try directory(selection, in: cache[browser] ?? [])
        }
        var out = config
        out.defaultProfile = try resolve(config.browser, config.defaultProfile)
        for index in out.rules.indices {
            out.rules[index].profile = try resolve(
                config.browser(of: config.rules[index]), config.rules[index].profile)
        }
        return out
    }
}
