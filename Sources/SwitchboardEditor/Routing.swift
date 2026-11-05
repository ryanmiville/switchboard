import Foundation
import SwitchboardCore

// Opening a link that the system handed the app, and how long the app lives afterwards.

/// Why a link couldn't be opened, and the rule that sent it there, if one matched, so Settings can
/// offer to fix that rule.
public struct LinkFailure: Equatable, Sendable {
    public var reason: String
    public var rule: RuleID?

    public init(reason: String, rule: RuleID? = nil) {
        self.reason = reason
        self.rule = rule
    }
}

public enum Routing {
    /// Seconds a link-only launch waits after its latest link before quitting.
    public static let idleExit = 0.5

    /// Opens `link` where `config` routes it and records it in history. A history failure never
    /// fails the link. Returns why the link couldn't be opened.
    public static func open(
        _ link: String, config: Config, browsers: Browsers, history: HistoryStore, now: Timestamp
    ) -> LinkFailure? {
        let decision = Router.decide(config, link: link)
        var failure: String?
        do {
            try Launch.launch(link, at: decision.destination, browsers: browsers)
        } catch {
            failure = error.description
        }
        // Best effort, and already kept for `doctor`.
        History.record(
            link, destination: decision.destination,
            origin: decision.rule.map(History.Origin.rule) ?? .default,
            config: config, error: failure, now: now, store: history, browsers: browsers)
        return failure.map { LinkFailure(reason: $0, rule: decision.rule.map { config.rules[$0].id }) }
    }

    /// A link from the system, as the app handles it: pending edits are saved first, so routing
    /// uses what the person sees. Returns why it couldn't be opened; the app shows that with
    /// recovery actions instead of opening the link anywhere else.
    public static func receive(_ link: String, editor: inout Editor, now: Timestamp) -> LinkFailure? {
        editor.checkExternal()
        guard Link.isWeb(link) || Link.isLocalFile(link) else {
            return LinkFailure(reason: LaunchError.invalidURL.description)
        }
        guard editor.flush() else {
            return LinkFailure(reason: editor.error ?? "Your settings couldn’t be saved.")
        }
        let failure = open(
            link, config: editor.config, browsers: editor.browsers, history: editor.history, now: now)
        editor.loadRecent()
        return failure
    }

    /// What the URL tester in Settings shows for `link`, and whether it is a usable link.
    public static func describe(_ link: String, editor: Editor) -> (text: String, ok: Bool) {
        guard Link.isWeb(link) || Link.isLocalFile(link) else {
            return ("Enter a complete link, such as https://example.com/page.", false)
        }
        let config = editor.config
        let decision = Router.decide(config, link: link)
        let d = decision.destination
        let target =
            "\(editor.browserName(d.browser)) · \(editor.profileName(browser: d.browser, profile: d.profile))"
        guard let i = decision.rule else { return ("No rule matches → the default, \(target)", true) }
        let rule = config.rules[i]
        return ("Rule \(i + 1) (\(rule.condition.rawValue) \(rule.value)) → \(target)", true)
    }
}

/// When a link launch may quit. A launch that only delivers links exits shortly after the latest
/// one; opening the app any other way (at login, from Finder, Settings) keeps it running.
public struct RoutingSession: Equatable, Sendable {
    private var receivedLink = false
    private var resident = false
    private var latest: UInt64 = 0

    public init() {}

    /// The app finished launching. Without a link it is a normal, resident launch.
    public mutating func finishLaunching(atLogin: Bool) {
        if atLogin || !receivedLink { resident = true }
    }

    public mutating func stayResident() { resident = true }

    public var isResident: Bool { resident }

    /// Returns a ticket for this link; only the latest ticket may quit the app.
    public mutating func receiveLink() -> UInt64 {
        receivedLink = true
        latest += 1
        return latest
    }

    public func shouldQuit(after ticket: UInt64) -> Bool {
        receivedLink && !resident && ticket == latest
    }
}

/// Follows a file while the app runs, so changes made through the CLI show up in an open Settings
/// window and reach the picker. A thread compares the file's size and modification time twice a
/// second: cheap, and it survives the atomic rename every save does (a watch on the file itself
/// would follow the replaced inode).
public final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()
    private var stopped = false

    public init(_ url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "config-watch"
        thread.start()
    }

    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    private func stamp() -> [String]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return ["\(attributes[.modificationDate] ?? "")", "\(attributes[.size] ?? "")"]
    }

    private func run() {
        var last = stamp()
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            lock.lock()
            let done = stopped
            lock.unlock()
            if done { return }
            let now = stamp()
            if now != last {
                last = now
                onChange()
            }
        }
    }
}
