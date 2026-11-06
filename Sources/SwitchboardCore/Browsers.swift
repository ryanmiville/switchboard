import Foundation

// Browsers as macOS app bundles: the Chromium browsers, and Safari. A browser is identified by its
// bundle identifier. A Chromium browser's profiles live in a folder under ~/Library/Application
// Support that each browser names its own way, so the table below lists them rather than deriving
// them. Safari offers no way to choose one of its profiles from outside it, so it has one
// destination of its own (see `Profiles.read`).
//
// Discovery only reads files: Info.plist through PropertyListSerialization, never Bundle, so it
// builds and is tested on Linux as well as on the Mac.

/// The browsers Switchboard supports.
public enum Family: String, CaseIterable, Sendable {
    case chrome, chromeBeta, chromeDev, chromeCanary, chromium, brave, edge, edgeBeta, edgeDev, edgeCanary
    case opera, operaBeta, operaDeveloper, vivaldi, arc, helium
    case safari, safariTechnologyPreview

    /// Whether the browser is Chromium-based, with profiles in `Local State` and a
    /// `--profile-directory` argument. Safari is not.
    public var isChromium: Bool { self != .safari && self != .safariTechnologyPreview }

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

/// A supported browser on this machine.
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
    /// The browser's user-data folder. A Chromium browser's holds `Local State` and the profiles;
    /// Switchboard reads nothing from Safari's.
    public var userData: URL

    /// Whether `query` names this browser: its name, an alias, or its family's short name (such as
    /// "Chrome"), ignoring case.
    public func answers(to query: String) -> Bool {
        ([name] + aliases + [family.shortName].compactMap { $0 }).contains {
            $0.compare(query, options: .caseInsensitive) == .orderedSame
        }
    }
}

/// Finds supported browsers in a list of application folders.
public struct Browsers: Sendable {
    /// Bundle identifiers, the family each belongs to, and its user-data folder under ~/Library.
    public static let bundles: [(id: String, family: Family, data: String)] = [
        ("com.google.Chrome", .chrome, "Application Support/Google/Chrome"),
        ("com.google.Chrome.beta", .chromeBeta, "Application Support/Google/Chrome Beta"),
        ("com.google.Chrome.dev", .chromeDev, "Application Support/Google/Chrome Dev"),
        ("com.google.Chrome.canary", .chromeCanary, "Application Support/Google/Chrome Canary"),
        ("org.chromium.Chromium", .chromium, "Application Support/Chromium"),
        ("com.brave.Browser", .brave, "Application Support/BraveSoftware/Brave-Browser"),
        ("com.microsoft.edgemac", .edge, "Application Support/Microsoft Edge"),
        ("com.microsoft.edgemac.Beta", .edgeBeta, "Application Support/Microsoft Edge Beta"),
        ("com.microsoft.edgemac.Dev", .edgeDev, "Application Support/Microsoft Edge Dev"),
        ("com.microsoft.edgemac.Canary", .edgeCanary, "Application Support/Microsoft Edge Canary"),
        ("com.operasoftware.Opera", .opera, "Application Support/com.operasoftware.Opera"),
        ("com.operasoftware.OperaNext", .operaBeta, "Application Support/com.operasoftware.OperaNext"),
        (
            "com.operasoftware.OperaDeveloper", .operaDeveloper,
            "Application Support/com.operasoftware.OperaDeveloper"
        ),
        ("com.opera.Opera", .opera, "Application Support/com.operasoftware.Opera"),
        ("com.opera.OperaBeta", .operaBeta, "Application Support/com.operasoftware.OperaNext"),
        ("com.opera.OperaDeveloper", .operaDeveloper, "Application Support/com.operasoftware.OperaDeveloper"),
        ("com.vivaldi.Vivaldi", .vivaldi, "Application Support/Vivaldi"),
        ("company.thebrowser.Browser", .arc, "Application Support/Arc/User Data"),
        ("com.keksbay.Arc", .arc, "Application Support/Arc/User Data"),
        ("net.imput.helium", .helium, "Application Support/net.imput.helium"),
        ("com.apple.Safari", .safari, "Safari"),
        ("com.apple.SafariTechnologyPreview", .safariTechnologyPreview, "SafariTechnologyPreview"),
    ]

    /// macOS's `open`, which opens links in Safari: Safari has no command-line arguments and runs
    /// as a single process, so its executable can't be run a second time.
    public static let systemOpener = URL(fileURLWithPath: "/usr/bin/open")

    public var home: Home
    public var applicationDirectories: [URL]
    /// The program that opens a link in a browser without profiles (`open -a <app> <link>`).
    /// Tests point it at a recording program.
    public var opener: URL

    /// Browsers found in `applicationDirectories`.
    public init(home: Home, applicationDirectories: [URL], opener: URL = Browsers.systemOpener) {
        self.home = home
        self.applicationDirectories = applicationDirectories
        self.opener = opener
    }

    /// `/Applications` and `~/Applications`, or only `$SWITCHBOARD_APPLICATIONS` when it is set.
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
    /// when nothing is there or it isn't a supported browser.
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
            userData: home.appending("Library/\(bundle.data)"))
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
