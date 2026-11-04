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

/// What the focused browser window showed when the panel was summoned.
public struct BrowserTab: Equatable, Sendable {
    /// The active tab's link, exactly as the browser reported it.
    public var link: String
    /// The window's title. On the Mac, Chrome and Helium give only the page's title; a browser that
    /// ends it with the profile's name ("… - Work") lets the panel tell which profile it is.
    public var windowTitle: String?

    public init(link: String, windowTitle: String? = nil) {
        self.link = link
        self.windowTitle = windowTitle
    }
}

/// Why the current tab's link couldn't be read.
public enum TabError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedBrowser, automationDenied, noTab, notWeb, unreadable

    public var description: String {
        switch self {
        case .unsupportedBrowser: "Focus a supported browser and try the shortcut again."
        case .automationDenied:
            "\(Identity.appName) isn’t allowed to read this browser. In System Settings → Privacy & Security → Automation, turn on the browser under \(Identity.appName), then try again."
        case .noTab: "The browser has no open tab. Open a web page and try again."
        case .notWeb: "This tab isn’t an HTTP or HTTPS page, so there’s nothing to open."
        case .unreadable: "The current tab couldn’t be read. Try the shortcut again from the browser."
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

    /// The destination the browser window is showing, so the panel can leave it out. Only that
    /// browser's profiles are considered (the same name in another browser is someone else), and the
    /// first of these that answers wins:
    ///
    /// 1. the browser's only profile;
    /// 2. the profile whose name ends the window's title, in browsers that add it;
    /// 3. the only profile with windows open, from `activity`;
    /// 4. with several open, the one used last.
    ///
    /// `nil` when it can't tell, so nothing is left out.
    public static func current(
        windowTitle: String?, browserID: String, installed: [BrowserInfo], choices: [Choice],
        activity: ProfileActivity = ProfileActivity()
    ) -> Destination? {
        guard let browser = installed.first(where: { $0.id == browserID }) else { return nil }
        let profiles = choices.filter { $0.destination.browser == browser.locator && $0.error == nil }
        func profile(_ directory: String?) -> Destination? {
            profiles.first { $0.destination.profile == directory }?.destination
        }
        if profiles.count == 1 { return profiles[0].destination }
        if let title = windowTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            let named = profiles.filter { choice in
                [" - ", " – ", " — "].contains { title.hasSuffix($0 + choice.profileName) }
            }
            // "Work" and "Side Work" both end "… - Side Work"; the longer name is the one shown.
            if let found = named.max(by: { $0.profileName.count < $1.profileName.count }) {
                return found.destination
            }
        }
        let open = activity.open.filter { profile($0) != nil }
        if open.count == 1 { return profile(open[0]) }
        if open.count > 1, let last = activity.lastUsed, open.contains(last) { return profile(last) }
        return nil
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
    /// What's typed in the panel, which narrows the destinations.
    public var query = ""
    /// The destination the link is being switched from, left out of the list.
    public var current: Destination?

    public init() {}

    /// The destinations the settings allow, favorites first, without the one being switched from,
    /// narrowed by the query.
    public var shown: [Choice] {
        all.filter { settings.includes($0.destination) && $0.destination != current && matches($0) }
    }

    /// Every word typed appears in the profile's or the browser's name, ignoring case and accents.
    func matches(_ choice: Choice) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let name = "\(choice.profileName) \(choice.browserName)"
        return words.allSatisfy {
            name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Narrows the list and selects its first destination.
    public mutating func setQuery(_ query: String) {
        self.query = query
        selected = 0
    }

    /// The index in `shown` that ⌘`n` opens: the first nine destinations, in order.
    public func number(_ n: Int) -> Int? {
        (1...9).contains(n) && shown.indices.contains(n - 1) ? n - 1 : nil
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
        query = ""
        current = nil
    }

    /// What the tab reader found in the browser with bundle identifier `browserID`.
    public mutating func tabRead(
        _ result: Result<BrowserTab, TabError>, browserID: String?, installed: [BrowserInfo]
    ) {
        switch result {
        case .success(let tab):
            link = tab.link
            current = browserID.flatMap { id in
                QuickSwitch.current(
                    windowTitle: tab.windowTitle, browserID: id, installed: installed, choices: all,
                    activity: installed.first { $0.id == id }.map(Profiles.activity) ?? ProfileActivity())
            }
            selected = 0
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
        guard !link.isEmpty else {
            // Nothing was read; the reason is already shown, or the browser wasn't one we read.
            if error == nil { error = TabError.unsupportedBrowser.description }
            return nil
        }
        if let error = choice.error {
            self.error = error
            return nil
        }
        guard Link.isWeb(link) else {
            error = TabError.notWeb.description
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
}
