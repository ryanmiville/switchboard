import Foundation

// Chromium browsers as macOS app bundles. A browser is identified by its bundle identifier; its
// profiles live in a folder under ~/Library/Application Support that each browser names its own
// way, so the table below lists them rather than deriving them.
//
// Discovery only reads files: Info.plist through PropertyListSerialization, never Bundle, so it
// builds and is tested on Linux as well as on the Mac.

/// The Chromium browsers Switchboard supports.
public enum Family: String, CaseIterable, Sendable {
    case chrome, chromeBeta, chromeDev, chromeCanary, chromium, brave, edge, edgeBeta, edgeDev, edgeCanary
    case opera, operaBeta, operaDeveloper, vivaldi, arc, helium

    /// A name people use for the browser that differs from its full name, if any.
    public var shortName: String? {
        switch self {
        case .chrome: "Chrome"
        case .edge: "Edge"
        case .brave: "Brave"
        default: nil
        }
    }
}

/// A supported Chromium browser on this machine.
public struct BrowserInfo: Equatable, Sendable {
    /// What config.json stores for this browser: the `.app` path.
    public var locator: String
    /// The name people see, such as "Google Chrome".
    public var name: String
    /// The bundle identifier.
    public var id: String
    public var family: Family
    /// Other names the browser goes by, such as "Chrome". Matched case-insensitively.
    public var aliases: [String]
    /// The program to run.
    public var executable: URL
    /// The browser's user-data folder, which holds `Local State` and the profiles.
    public var userData: URL

    /// Whether `query` names this browser: its name, an alias, or its family's short name (such as
    /// "Chrome"), ignoring case.
    public func answers(to query: String) -> Bool {
        ([name] + aliases + [family.shortName].compactMap { $0 }).contains {
            $0.compare(query, options: .caseInsensitive) == .orderedSame
        }
    }
}

/// Finds supported Chromium browsers in a list of application folders.
public struct Browsers: Sendable {
    /// Bundle identifiers, the family each belongs to, and its user-data folder under
    /// ~/Library/Application Support.
    public static let bundles: [(id: String, family: Family, data: String)] = [
        ("com.google.Chrome", .chrome, "Google/Chrome"),
        ("com.google.Chrome.beta", .chromeBeta, "Google/Chrome Beta"),
        ("com.google.Chrome.dev", .chromeDev, "Google/Chrome Dev"),
        ("com.google.Chrome.canary", .chromeCanary, "Google/Chrome Canary"),
        ("org.chromium.Chromium", .chromium, "Chromium"),
        ("com.brave.Browser", .brave, "BraveSoftware/Brave-Browser"),
        ("com.microsoft.edgemac", .edge, "Microsoft Edge"),
        ("com.microsoft.edgemac.Beta", .edgeBeta, "Microsoft Edge Beta"),
        ("com.microsoft.edgemac.Dev", .edgeDev, "Microsoft Edge Dev"),
        ("com.microsoft.edgemac.Canary", .edgeCanary, "Microsoft Edge Canary"),
        ("com.operasoftware.Opera", .opera, "com.operasoftware.Opera"),
        ("com.operasoftware.OperaNext", .operaBeta, "com.operasoftware.OperaNext"),
        ("com.operasoftware.OperaDeveloper", .operaDeveloper, "com.operasoftware.OperaDeveloper"),
        ("com.opera.Opera", .opera, "com.operasoftware.Opera"),
        ("com.opera.OperaBeta", .operaBeta, "com.operasoftware.OperaNext"),
        ("com.opera.OperaDeveloper", .operaDeveloper, "com.operasoftware.OperaDeveloper"),
        ("com.vivaldi.Vivaldi", .vivaldi, "Vivaldi"),
        ("company.thebrowser.Browser", .arc, "Arc/User Data"),
        ("com.keksbay.Arc", .arc, "Arc/User Data"),
        ("net.imput.helium", .helium, "net.imput.helium"),
    ]

    public var home: Home
    public var applicationDirectories: [URL]

    /// Browsers found in `applicationDirectories`.
    public init(home: Home, applicationDirectories: [URL]) {
        self.home = home
        self.applicationDirectories = applicationDirectories
    }

    /// `/Applications` and `~/Applications`, or only `$SWITCHBOARD_NEXT_APPLICATIONS` when it is set.
    public init(home: Home, env: Env) {
        self.init(
            home: home,
            applicationDirectories: env.applicationDirectories
                ?? [URL(fileURLWithPath: "/Applications", isDirectory: true), home.appending("Applications")])
    }

    /// Browsers installed in the application folders, sorted by name then locator.
    public func installed() -> [BrowserInfo] {
        var found: [BrowserInfo] = []
        for directory in applicationDirectories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names where name.hasSuffix(".app") {
                if let info = at(directory.appendingPathComponent(name).path),
                    !found.contains(where: { $0.locator == info.locator })
                {
                    found.append(info)
                }
            }
        }
        return Self.sorted(found)
    }

    /// The supported browser at `locator`, whether or not it is in the application folders. `nil`
    /// when nothing is there or it isn't a supported Chromium browser.
    public func at(_ locator: String) -> BrowserInfo? {
        let path = Self.standardized(locator)
        let plistURL = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Files.contents(of: plistURL),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let id = dict["CFBundleIdentifier"] as? String,
            let bundle = Self.bundles.first(where: { $0.id == id }),
            let executable = dict["CFBundleExecutable"] as? String
        else { return nil }
        let name = Self.fileStem(path)
        var aliases: [String] = []
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let alias = dict[key] as? String, alias != name, aliases.last != alias {
                aliases.append(alias)
            }
        }
        return BrowserInfo(
            locator: path, name: name, id: id, family: bundle.family, aliases: aliases,
            executable: URL(fileURLWithPath: path).appendingPathComponent("Contents/MacOS/\(executable)"),
            userData: home.appending("Library/Application Support/\(bundle.data)"))
    }

    /// `locator` in the form `BrowserInfo.locator` uses, so two spellings compare equal.
    public func standardize(_ locator: String) -> String { at(locator)?.locator ?? locator }

    /// The browser's name, or the locator's file name when it isn't available.
    public func displayName(_ locator: String) -> String { at(locator)?.name ?? Self.fileStem(locator) }

    /// Installed browsers plus any supported browser at one of `extra` (such as those the config
    /// names), without duplicates, sorted by name then locator.
    public func known(_ extra: [String]) -> [BrowserInfo] {
        var all = installed()
        for locator in extra {
            if let info = at(locator), !all.contains(where: { $0.locator == info.locator }) {
                all.append(info)
            }
        }
        return Self.sorted(all)
    }

    public static func sorted(_ browsers: [BrowserInfo]) -> [BrowserInfo] {
        browsers.sorted {
            let (a, b) = ($0.name.lowercased(), $1.name.lowercased())
            return a != b ? Array(a.utf8).lexicographicallyPrecedes(Array(b.utf8)) : $0.locator < $1.locator
        }
    }

    /// The last path component without its extension (`/Applications/Helium.app` → `Helium`).
    public static func fileStem(_ locator: String) -> String {
        let last = locator.split(separator: "/").last.map(String.init) ?? locator
        guard let dot = last.lastIndex(of: "."), dot != last.startIndex else { return last }
        return String(last[..<dot])
    }

    /// Removes `.`, `..` and trailing slashes without touching the disk.
    static func standardized(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": _ = parts.popLast()
            default: parts.append(part)
            }
        }
        return (path.hasPrefix("/") ? "/" : "") + parts.joined(separator: "/")
    }
}
