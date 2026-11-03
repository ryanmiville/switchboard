import Foundation
import SwitchboardCore

// Quick Switch: a panel that opens the focused browser's current page in another browser profile,
// chosen by hand. It bypasses the routing rules on purpose. This is its model; the panel and the
// reading of the current tab are in SwitchboardUI and SwitchboardMac.

/// One destination in the panel.
public struct Choice: Equatable, Sendable {
    public var destination: Destination
    public var browserName: String
    public var profileName: String
    public var favorite: Bool
    /// Why it can't be opened: the browser or profile is gone, or its profiles can't be read.
    public var error: String?

    public var label: String { "\(browserName) · \(profileName)" }
}

/// Why the current tab's link couldn't be read.
public enum TabError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedBrowser, automationDenied, noTab, notWeb, unreadable

    public var description: String {
        switch self {
        case .unsupportedBrowser:
            "Focus a supported browser and try the shortcut again, or paste a link above."
        case .automationDenied:
            "\(Identity.appName) isn’t allowed to read this browser. In System Settings → Privacy & Security → Automation, turn on the browser under \(Identity.appName). You can also paste the link above."
        case .noTab: "The browser has no open tab. Open a web page and try again, or paste a link above."
        case .notWeb: "This tab isn’t an HTTP or HTTPS page. Paste a complete web link above."
        case .unreadable:
            "The current tab couldn’t be read. Try again from the browser, or copy its address and paste it above."
        }
    }
}

/// Whether the app opens when the person logs in.
public enum LoginStatus: Equatable, Sendable {
    case disabled, enabled
    /// Registered, but waiting for the person to allow it in System Settings.
    case requiresApproval
}

public enum QuickSwitch {
    static let unavailable =
        "This browser or profile is unavailable. Refresh, or hide it in Quick Switch settings."

    /// Every destination: favorites first in their saved order, then each installed browser's
    /// profiles, then destinations the settings name that aren't installed (shown with an error,
    /// never replaced by a similar one in another browser), then browsers whose profiles couldn't
    /// be read.
    public static func choices(_ installed: [BrowserInfo], _ settings: PickerSettings) -> [Choice] {
        var found: [Choice] = []
        var errors: [(String, String)] = []
        for browser in installed {
            do {
                for p in try Profiles.read(browser) {
                    found.append(
                        Choice(
                            destination: Destination(browser: browser.locator, profile: p.directory),
                            browserName: browser.name, profileName: p.name, favorite: false))
                }
            } catch {
                errors.append((browser.locator, error.description))
            }
        }
        func errorOf(_ locator: String) -> String? { errors.first { $0.0 == locator }?.1 }
        var pinned: [Choice] = []
        for f in settings.favorites where !pinned.contains(where: { $0.destination == f.destination }) {
            let exists = found.contains { $0.destination == f.destination }
            pinned.append(
                Choice(
                    destination: f.destination,
                    browserName: installed.first { $0.locator == f.browser }?.name
                        ?? Browsers.fileStem(f.browser),
                    profileName: f.name, favorite: true,
                    error: exists ? nil : (errorOf(f.browser) ?? unavailable)))
        }
        found.removeAll { c in pinned.contains { $0.destination == c.destination } }
        for d in settings.destinations ?? [] where !(pinned + found).contains(where: { $0.destination == d })
        {
            found.append(
                Choice(
                    destination: d, browserName: Browsers.fileStem(d.browser), profileName: d.profile,
                    favorite: false,
                    error: errorOf(d.browser) ?? unavailable))
        }
        for (locator, error) in errors
        where !(pinned + found).contains(where: { $0.destination.browser == locator }) {
            found.append(
                Choice(
                    destination: Destination(browser: locator, profile: ""),
                    browserName: Browsers.fileStem(locator),
                    profileName: "Profiles unavailable", favorite: false, error: error))
        }
        return pinned + found
    }
}

/// The panel's state: the link, the destinations, and what went wrong.
public struct PickerState: Sendable {
    public var link = ""
    public var error: String?
    /// The error is a missing Automation permission, so the panel offers its settings.
    public var needsPermission = false
    /// Every destination, hidden ones included.
    public var all: [Choice] = []
    public var settings = PickerSettings()
    /// Index into `shown`.
    public var selected = 0
    public var config = Config.defaults

    public init() {}

    /// The destinations the settings allow, favorites first.
    public var shown: [Choice] { all.filter { settings.includes($0.destination) } }

    /// The index in `shown` of the favorite numbered `n` (1-based), for ⌘1–⌘9.
    public func favorite(_ n: Int) -> Int? {
        guard n >= 1 else { return nil }
        let indices = shown.indices.filter { shown[$0].favorite }
        return indices.count >= n ? indices[n - 1] : nil
    }

    /// Reads the saved config and lists the destinations again.
    public mutating func refresh(store: ConfigStore, browsers: Browsers) {
        if let snapshot = try? store.load() { config = snapshot.config }
        settings = config.picker ?? PickerSettings()
        all = QuickSwitch.choices(browsers.installed(), settings)
        selected = min(selected, max(shown.count - 1, 0))
    }

    /// Starts a new summon: clears the last link and error.
    public mutating func reset() {
        link = ""
        error = nil
        needsPermission = false
        selected = 0
    }

    /// What the tab reader found.
    public mutating func tabRead(_ result: Result<String, TabError>) {
        switch result {
        case .success(let link): self.link = link
        case .failure(let e):
            error = e.description
            needsPermission = e == .automationDenied
        }
    }

    /// Moves the selection, wrapping around.
    public mutating func moveSelection(by offset: Int) {
        let count = shown.count
        guard count > 0 else { return }
        selected = ((selected + offset) % count + count) % count
    }

    /// Opens the link in the shown destination at `index`. Returns the destination opened, or
    /// `nil` with `error` set. Pending Settings edits should be flushed by the caller first.
    public mutating func open(_ index: Int, browsers: Browsers, history: HistoryStore, now: Timestamp)
        -> Destination?
    {
        let shown = self.shown
        guard shown.indices.contains(index) else { return nil }
        let choice = shown[index]
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.isEmpty && needsPermission { return nil }
        if let error = choice.error {
            self.error = error
            return nil
        }
        guard Link.isWeb(link) else {
            error = "Enter a complete HTTP or HTTPS link, such as https://example.com."
            return nil
        }
        var failure: String?
        do {
            try Launch.launch(link, at: choice.destination, browsers: browsers)
        } catch {
            failure = error.description
        }
        History.record(
            link, destination: choice.destination, origin: .picker, config: config, error: failure, now: now,
            store: history, browsers: browsers)
        if let failure {
            error = "\(failure) Refresh the destinations or open Settings to fix the issue."
            return nil
        }
        return choice.destination
    }

    /// The picker settings with the shown destination at `index` starred or unstarred. The caller
    /// saves them through the editor, so the two never write over each other.
    public mutating func toggleFavorite(_ index: Int, browsers: Browsers) -> PickerSettings? {
        let shown = self.shown
        guard shown.indices.contains(index) else { return nil }
        let choice = shown[index]
        var settings = self.settings
        if settings.favorites.contains(where: { $0.destination == choice.destination }) {
            settings.favorites.removeAll { $0.destination == choice.destination }
        } else if choice.error == nil {
            settings.favorites.append(
                Favorite(
                    browser: choice.destination.browser, profile: choice.destination.profile,
                    name: choice.profileName))
        }
        self.settings = settings
        all = QuickSwitch.choices(browsers.installed(), settings)
        return settings
    }
}
