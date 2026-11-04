import Foundation
import SwitchboardCore

// Fixture homes and browsers for tests and scenes. A fixture browser is a real app bundle in a
// temporary folder: an Info.plist with a supported bundle identifier, and a shell script as its
// executable that appends its arguments to a log instead of opening anything. Nothing here reads
// or writes the real home folder.

/// A temporary home folder, removed by `remove()`.
public struct TemporaryHome: Sendable {
    public let home: Home

    public init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("switchboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        home = Home(url.resolvingSymlinksInPath())
    }

    /// The folder fixture browsers go in; point `$SWITCHBOARD_APPLICATIONS` at it.
    public var applications: URL { home.appending("Applications") }

    /// The log every fixture browser in this home appends its launches to.
    public var launchLog: URL { home.appending("launches.log") }

    /// Browser discovery limited to this home's fixture folder.
    public var browsers: Browsers { Browsers(home: home, applicationDirectories: [applications]) }

    /// The environment a binary under test gets, limited to this home's fixture folder.
    public var environment: [String: String] {
        ["HOME": home.path, Env.applicationsVariable: applications.path]
    }

    public var configStore: ConfigStore { ConfigStore(url: home.configFile) }
    public var historyStore: HistoryStore { HistoryStore(url: home.historyFile) }

    public func remove() {
        try? FileManager.default.removeItem(at: home.url)
    }

    /// Installs `<applications>/<name>.app` as a browser of `family`, gives it `profiles`
    /// (directory, display name), and returns its locator.
    @discardableResult
    public func installBrowser(
        _ family: Family, name: String, profiles: [(String, String)] = [("Default", "Default")]
    )
        throws -> String
    {
        guard let bundle = Browsers.bundles.first(where: { $0.family == family }) else {
            throw FixtureError("No bundle identifier for \(family).")
        }
        let app = applications.appendingPathComponent("\(name).app")
        let executable = name.replacingOccurrences(of: " ", with: "")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: String] = [
            "CFBundleIdentifier": bundle.id, "CFBundleExecutable": executable, "CFBundleName": name,
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Self.writeRecordingProgram(macOS.appendingPathComponent(executable), log: launchLog)
        try writeLocalState(bundle.data, profiles)
        return app.path
    }

    /// Writes the browser's Local State with `profiles` (directory, display name), and, as
    /// Chromium records them, the profiles with windows open and the one used last.
    public func writeLocalState(
        _ dataFolder: String, _ profiles: [(String, String)], open: [String]? = nil, lastUsed: String? = nil
    ) throws {
        try writeLocalState(
            in: home.appending("Library/Application Support/\(dataFolder)"), profiles, open: open,
            lastUsed: lastUsed)
    }

    /// Rewrites `browser`'s Local State, as `writeLocalState(_:_:open:lastUsed:)` does.
    public func writeLocalState(
        of browser: BrowserInfo, _ profiles: [(String, String)], open: [String]? = nil,
        lastUsed: String? = nil
    ) throws {
        try writeLocalState(in: browser.userData, profiles, open: open, lastUsed: lastUsed)
    }

    private func writeLocalState(
        in folder: URL, _ profiles: [(String, String)], open: [String]?, lastUsed: String?
    ) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var cache: [String: Any] = [:]
        for (directory, name) in profiles { cache[directory] = ["name": name] }
        var profile: [String: Any] = ["info_cache": cache]
        if let open { profile["last_active_profiles"] = open }
        if let lastUsed { profile["last_used"] = lastUsed }
        try JSONSerialization.data(withJSONObject: ["profile": profile])
            .write(to: folder.appendingPathComponent("Local State"))
    }

    /// The launches the fixture browsers logged, oldest first, each as its argument list.
    public func recordedLaunches() -> [[String]] {
        Self.recordedLaunches(launchLog)
    }

    /// Waits up to about five seconds for `count` launches to be logged, since a launched program
    /// runs on its own, and returns what was logged.
    public func waitForLaunches(_ count: Int) -> [[String]] {
        for _ in 0..<500 {
            let launches = recordedLaunches()
            if launches.count >= count { return launches }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return recordedLaunches()
    }

    /// Writes a shell script that appends one line per run to `log`, with its arguments separated
    /// by tabs, and opens nothing.
    public static func writeRecordingProgram(_ program: URL, log: URL) throws {
        let quoted = log.path.replacingOccurrences(of: "'", with: "'\\''")
        // The whole line goes out in one write, so a reader never sees half a launch.
        let script =
            "#!/bin/sh\nline=''\nfor a in \"$@\"; do line=\"$line$a\t\"; done\nprintf '%s\\n' \"$line\" >> '\(quoted)'\n"
        try Data(script.utf8).write(to: program)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
    }

    /// Only finished lines: a launch still being written isn't counted until its newline is.
    public static func recordedLaunches(_ log: URL) -> [[String]] {
        guard let data = try? Data(contentsOf: log) else { return [] }
        var text = String(decoding: data, as: UTF8.self)
        if let end = text.lastIndex(of: "\n") { text = String(text[...end]) } else { return [] }
        return text.split(separator: "\n").map { line in
            var text = String(line)
            if text.hasSuffix("\t") { text.removeLast() }
            return text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }
    }
}

public struct FixtureError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
