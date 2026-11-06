import Foundation
import SwitchboardCore

// The settings window's model, with no drawing: the config being edited, autosave, and what
// happens when the file changes underneath (the CLI writes it too).
//
// - Edits mark the config dirty; `poll(now:)` saves it `Editor.autosaveDelay` seconds later.
// - Every save is a compare-and-swap against the revision this editor last loaded or saved.
// - A file that changed elsewhere reloads silently when there are no pending edits. With pending
//   edits it is a conflict: the edits stay, and the person chooses to keep them or the saved file.
// - Saves store every profile as its directory identifier, resolved in its own browser.

public struct Editor: Sendable {
    /// Seconds between the last edit and its save.
    public static let autosaveDelay = 0.5

    public static let conflictMessage =
        "The settings file changed outside this window, for example through \(Identity.cliName), while you had unsaved changes. Your changes are still here: keep them to replace the file, or use the saved settings."

    public private(set) var config = Config.defaults
    public let home: Home
    public let store: ConfigStore
    public let history: HistoryStore
    public let browsers: Browsers
    /// Installed browsers, for the browser menus.
    public private(set) var installed: [BrowserInfo] = []
    /// Each browser the config names, with its profiles or why they couldn't be read.
    public private(set) var profiles: [String: Result<[Profile], ProfileError>] = [:]
    /// The file couldn't be read or parsed. Nothing is saved until it is fixed and reloaded.
    public private(set) var loadError: String?
    public private(set) var saveError: String?
    /// A profile no longer resolves, or none is chosen; saving waits until it does.
    public private(set) var profileError: String?
    /// The file changed elsewhere while edits were pending.
    public private(set) var conflict = false
    public private(set) var historyError: String?
    /// The newest links in history, newest first, as of the last `loadRecent()`.
    public private(set) var recent: [History.Entry] = []
    /// History couldn't be read.
    public private(set) var recentError: String?
    /// Whether the file existed when it was last loaded.
    public private(set) var fileExists = false
    private var revision: String?
    private var dirty = false
    /// When the pending save is due, in the caller's clock; `nil` until the next poll schedules it.
    private var saveAt: Double?

    /// Loads the config at `store` and lists installed browsers.
    public init(home: Home, store: ConfigStore, history: HistoryStore, browsers: Browsers) {
        self.home = home
        self.store = store
        self.history = history
        self.browsers = browsers
        installed = browsers.installed()
        reload()
        loadRecent()
    }

    public var hasUnsavedChanges: Bool { dirty && loadError == nil }

    /// The first error to show, in the order a person should fix them.
    public var error: String? { loadError ?? saveError ?? profileError }

    /// Changes the config and schedules a save. Refused while the file is unreadable.
    public mutating func edit(_ change: (inout Config) -> Void) {
        guard loadError == nil else { return }
        let before = config.browsers
        change(&config)
        if config.browsers != before { refreshProfiles() }
        dirty = true
        saveAt = nil
    }

    /// Saves when the autosave delay has passed. Returns the seconds until the next save is due, or
    /// `nil` when nothing is pending.
    public mutating func poll(now: Double) -> Double? {
        guard dirty, !conflict, loadError == nil else { return nil }
        let due = saveAt ?? (now + Self.autosaveDelay)
        saveAt = due
        if now >= due {
            flush()
            return nil
        }
        return due - now
    }

    /// Saves pending edits now: before routing a link, closing the window, or quitting. Returns
    /// whether everything is saved.
    @discardableResult
    public mutating func flush() -> Bool {
        saveAt = nil
        guard loadError == nil else { return false }
        guard dirty else { return true }
        let normalized: Config
        do {
            normalized = try Profiles.normalized(config, browsers)
        } catch {
            profileError = error.description
            return false
        }
        do {
            revision = try store.save(normalized, expecting: revision)
            config = normalized
            dirty = false
            saveError = nil
            profileError = nil
            conflict = false
            fileExists = true
            return true
        } catch .conflict {
            conflict = true
            saveError = Self.conflictMessage
            return false
        } catch {
            saveError = "Your changes couldn’t be saved. They are still here. \(error)"
            return false
        }
    }

    /// Reads the file again, dropping pending edits.
    public mutating func reload() {
        saveAt = nil
        do {
            let snapshot = try store.load()
            config = snapshot.config
            revision = snapshot.revision
            fileExists = snapshot.exists
            loadError = nil
            saveError = nil
            conflict = false
            dirty = false
            refreshProfiles()
        } catch {
            if case .invalid(_, let invalidRevision) = error {
                revision = invalidRevision
            } else {
                revision = nil
            }
            loadError =
                "Your settings couldn’t be read, so nothing will be saved. The file is unchanged: fix it, then reload. \(error)"
            fileExists = true
            dirty = false
        }
    }

    /// Follows the file when it changed elsewhere. With pending edits, reports a conflict instead.
    /// Returns true when something visible changed.
    @discardableResult
    public mutating func checkExternal() -> Bool {
        guard let current = try? store.currentRevision(), current != revision else { return false }
        if hasUnsavedChanges {
            conflict = true
            saveError = Self.conflictMessage
        } else {
            reload()
        }
        return true
    }

    /// Replaces the file that changed elsewhere with these edits, at the person's request.
    @discardableResult
    public mutating func keepMine() -> Bool {
        if conflict {
            revision = try? store.currentRevision()
            conflict = false
        }
        return flush()
    }

    /// Reads which profiles each named browser has, and whether every saved profile resolves.
    public mutating func refreshProfiles() {
        installed = browsers.installed()
        var found: [String: Result<[Profile], ProfileError>] = [:]
        for browser in config.browsers {
            found[browser] = Result { () throws(ProfileError) in try Profiles.of(browsers, browser) }
        }
        profiles = found
        do {
            _ = try Profiles.normalized(config, browsers)
            profileError = nil
        } catch {
            profileError = error.description
        }
    }

    /// The profiles of `browser`, read now if the config doesn't name it yet.
    public func profiles(of browser: String) -> [Profile] {
        switch profiles[browser] {
        case .success(let list): list
        case .failure: []
        case nil: (try? Profiles.of(browsers, browser)) ?? []
        }
    }

    /// The first profile `browser` lists, which a new choice of browser starts on, so a browser
    /// is never left without a profile. Empty when the browser has none to read.
    public func firstProfile(of browser: String) -> String {
        browser.isEmpty ? "" : profiles(of: browser).first?.directory ?? ""
    }

    public func browserName(_ browser: String) -> String {
        browser.isEmpty ? "Choose a browser" : browsers.displayName(browser)
    }

    /// The profile's display name, or what is saved when it doesn't resolve.
    public func profileName(browser: String, profile: String) -> String {
        if browser.isEmpty { return "Choose a browser first" }
        let list = profiles(of: browser)
        guard let directory = try? Profiles.directory(profile, in: list) else {
            return profile.isEmpty ? "Choose a profile" : "\(profile) (unavailable)"
        }
        return list.first { $0.directory == directory }?.name ?? directory
    }

    // MARK: Edits

    /// A new default browser, on its first profile. Profiles that inherited the old one were
    /// chosen there and can be different people in the new one, so they move to the first profile
    /// too instead of keeping a directory that means someone else.
    public mutating func selectDefaultBrowser(_ browser: String) {
        guard browser != config.browser else { return }
        let first = firstProfile(of: browser)
        edit { c in
            c.browser = browser
            c.defaultProfile = first
            for i in c.rules.indices where c.rules[i].browser == nil { c.rules[i].profile = first }
        }
    }

    public mutating func selectDefaultProfile(_ profile: String) {
        edit { $0.defaultProfile = profile }
    }

    public mutating func deleteRule(_ id: RuleID) {
        edit { $0.rules.removeAll { $0.id == id } }
    }

    /// Moves a rule up (`-1`) or down (`+1`).
    public mutating func moveRule(_ id: RuleID, by offset: Int) {
        guard let from = config.index(of: id) else { return }
        let to = from + offset
        guard config.rules.indices.contains(to) else { return }
        edit { $0.rules.swapAt(from, to) }
    }

    /// Moves a rule to position `to` (0-based), as a drag drops it.
    public mutating func moveRule(_ id: RuleID, to: Int) {
        guard let from = config.index(of: id) else { return }
        let to = max(0, min(to, config.rules.count - 1))
        guard from != to else { return }
        edit { c in
            let rule = c.rules.remove(at: from)
            c.rules.insert(rule, at: to)
        }
    }

    /// Adds a new rule or replaces the one with the same id.
    @discardableResult
    public mutating func commitRule(_ rule: Rule) -> Bool {
        guard loadError == nil else { return false }
        if let i = config.index(of: rule.id) {
            edit { $0.rules[i] = rule }
        } else {
            edit { $0.rules.append(rule) }
        }
        return true
    }

    /// Links from history, newest first, each once. Empty when history can't be read.
    public func recentLinks() -> [String] {
        var seen = Set<String>()
        return ((try? history.entries()) ?? []).map(\.url).filter { seen.insert($0).inserted }
    }

    public mutating func setPicker(_ settings: PickerSettings) {
        edit { $0.picker = settings }
    }

    public mutating func setHistoryEnabled(_ enabled: Bool) {
        // Omitted means enabled, which keeps the file minimal.
        edit { $0.history = enabled ? nil : HistorySettings(enabled: false) }
    }

    /// Reads history again, for the Recent Links pane.
    public mutating func loadRecent() {
        do {
            recent = try history.entries()
            recentError = nil
        } catch {
            recentError = "Recent links couldn’t be read. \(error.message)"
        }
    }

    public mutating func clearHistory() {
        do {
            try history.clear()
            historyError = nil
            recent = []
            recentError = nil
        } catch {
            historyError = "History couldn’t be cleared. \(error.message)"
        }
    }
}

/// A rule being added or edited. Only Done changes the config.
public struct Draft: Equatable, Sendable {
    public var id: RuleID
    public var isNew: Bool
    public var condition: Condition
    public var value: String
    /// `nil` inherits the default browser.
    public var browser: String?
    public var profile: String
    public var error: String?

    /// A new rule in the default browser, on `profile` (its first, from `Editor.firstProfile`).
    public static func newRule(profile: String = "") -> Draft {
        Draft(
            id: RuleID(), isNew: true, condition: .domain, value: "", browser: nil, profile: profile,
            error: nil)
    }

    public static func editing(_ rule: Rule) -> Draft {
        Draft(
            id: rule.id, isNew: false, condition: rule.condition, value: rule.value, browser: rule.browser,
            profile: rule.profile, error: nil)
    }

    /// The pattern as typed or pasted. A whole web link pasted into a Domain rule becomes its host,
    /// the part a Domain rule matches. Typing stays as typed: one character at a time, the start of
    /// a link would already have a host.
    public mutating func enterPattern(_ text: String) {
        let pasted = Self.inserted(from: value, to: text) > 1
        value = condition == .domain && pasted ? Self.host(of: text) ?? text : text
    }

    /// How many characters an edit from `old` to `new` put in at once, beyond what they share at
    /// either end.
    static func inserted(from old: String, to new: String) -> Int {
        let a = Array(old)
        let b = Array(new)
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var end = 0
        while end < a.count - start, end < b.count - start, a[a.count - 1 - end] == b[b.count - 1 - end] {
            end += 1
        }
        return b.count - start - end
    }

    /// A new way to match. Switching to Domain with a whole link in the pattern keeps its host.
    public mutating func selectCondition(_ condition: Condition) {
        self.condition = condition
        if condition == .domain, let host = Self.host(of: value) { value = host }
    }

    static func host(of text: String) -> String? {
        Link.webHost(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Changing the browser needs a new profile, since directory names belong to one browser: it
    /// starts on `firstProfile`, the new browser's first (from `Editor.firstProfile`).
    public mutating func selectBrowser(_ browser: String?, defaultBrowser: String, firstProfile: String) {
        if (browser ?? defaultBrowser) != (self.browser ?? defaultBrowser) { profile = firstProfile }
        self.browser = browser
    }

    /// The rule this draft describes, or why it can't be saved (also kept in `error`).
    public mutating func validated() -> Rule? {
        let value: String
        do {
            value = try RuleOperations.pattern(self.value)
            if condition == .domain { try RuleOperations.validateDomain(value) }
        } catch {
            self.error = error.message.replacingOccurrences(of: "--value", with: "The pattern")
            return nil
        }
        guard !profile.isEmpty else {
            error = "Choose a profile."
            return nil
        }
        error = nil
        var rule = Rule(condition, value, profile: profile, browser: browser)
        rule.id = id
        return rule
    }
}
