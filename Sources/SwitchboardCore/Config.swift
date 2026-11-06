import Foundation

// config.json: the default destination, the ordered rules, and optional picker and history
// settings. The CLI and the app share it with no daemon between them; see ConfigStore.
//
// Unknown keys are refused, so a typo in a hand or agent edit is reported instead of ignored.
// The current app's files still load: `routes` is read as `rules`, a rule without `browser`
// inherits the default browser, and the picker's old Carbon shortcut becomes a shortcut string.

/// How a rule's pattern is compared with a link.
public enum Condition: String, Codable, CaseIterable, Sendable {
    /// The link's host is the pattern or one of its subdomains.
    case domain
    /// The pattern appears anywhere in the link, ignoring case.
    case contains
    /// The pattern is the whole link, ignoring case.
    case exact

    public var label: String {
        switch self {
        case .contains: "Contains"
        case .exact: "Exact"
        case .domain: "Domain"
        }
    }
}

/// A browser and one of its profiles. `browser` is the app's path; `profile` is a Chromium profile
/// directory such as `Profile 1`, or, in old files, a display name. Safari's only profile is `Default`.
public struct Destination: Codable, Hashable, Sendable {
    public var browser: String
    public var profile: String

    public init(browser: String, profile: String) {
        self.browser = browser
        self.profile = profile
    }

    public init(from decoder: Decoder) throws {
        try decoder.refuseUnknownKeys(["browser", "profile"])
        let c = try decoder.container(keyedBy: AnyKey.self)
        browser = try c.decode(String.self, forKey: AnyKey("browser"))
        profile = try c.decode(String.self, forKey: AnyKey("profile"))
    }
}

/// Identifies a rule while it is in memory, so edits and moves can follow it. Never saved.
public struct RuleID: Hashable, Sendable {
    let value: UInt64

    public init() {
        value = RuleID.counter.next()
    }

    private static let counter = Counter()

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var last: UInt64 = 0
        func next() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            last += 1
            return last
        }
    }
}

/// One routing rule. The first rule that matches a link wins.
public struct Rule: Codable, Equatable, Sendable {
    public var id = RuleID()
    public var condition: Condition
    /// Empty patterns never match.
    public var value: String
    public var profile: String
    /// `nil` inherits the config's default browser.
    public var browser: String?

    public init(_ condition: Condition, _ value: String, profile: String, browser: String? = nil) {
        self.condition = condition
        self.value = value
        self.profile = profile
        self.browser = browser
    }

    enum CodingKeys: String, CodingKey { case condition, value, profile, browser }

    public init(from decoder: Decoder) throws {
        try decoder.refuseUnknownKeys(["browser", "condition", "profile", "value"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        condition = try c.decode(Condition.self, forKey: .condition)
        value = try c.decode(String.self, forKey: .value)
        profile = try c.decode(String.self, forKey: .profile)
        browser = try c.decodeIfPresent(String.self, forKey: .browser)
    }
}

/// The optional `history` section. Omitted means enabled.
public struct HistorySettings: Codable, Equatable, Sendable {
    public var enabled: Bool

    public init(enabled: Bool) { self.enabled = enabled }

    public init(from decoder: Decoder) throws {
        try decoder.refuseUnknownKeys(["enabled"])
        let c = try decoder.container(keyedBy: AnyKey.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: AnyKey("enabled")) ?? true
    }
}

public struct Config: Codable, Equatable, Sendable {
    /// The default browser. Empty until one is chosen; links then fail with a recovery action.
    public var browser: String
    public var defaultProfile: String
    public var rules: [Rule]
    public var picker: PickerSettings?
    public var history: HistorySettings?

    public init(
        browser: String = "", defaultProfile: String = "Default", rules: [Rule] = [],
        picker: PickerSettings? = nil,
        history: HistorySettings? = nil
    ) {
        self.browser = browser
        self.defaultProfile = defaultProfile
        self.rules = rules
        self.picker = picker
        self.history = history
    }

    /// What a missing file means: no default browser yet, the `Default` profile, no rules.
    public static let defaults = Config()

    enum CodingKeys: String, CodingKey { case browser, defaultProfile, rules, routes, picker, history }

    public init(from decoder: Decoder) throws {
        try decoder.refuseUnknownKeys(["browser", "defaultProfile", "history", "picker", "routes", "rules"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        browser = try c.decode(String.self, forKey: .browser)
        defaultProfile = try c.decode(String.self, forKey: .defaultProfile)
        if c.contains(.rules) && c.contains(.routes) {
            throw DecodingError.dataCorruptedError(
                forKey: .routes, in: c, debugDescription: "Use “rules” or the older “routes”, not both.")
        }
        rules =
            try c.decodeIfPresent([Rule].self, forKey: .rules) ?? c.decodeIfPresent(
                [Rule].self, forKey: .routes)
            ?? []
        picker = try c.decodeIfPresent(PickerSettings.self, forKey: .picker)
        history = try c.decodeIfPresent(HistorySettings.self, forKey: .history)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(browser, forKey: .browser)
        try c.encode(defaultProfile, forKey: .defaultProfile)
        try c.encode(rules, forKey: .rules)
        try c.encodeIfPresent(picker, forKey: .picker)
        try c.encodeIfPresent(history, forKey: .history)
    }

    public static func parse(_ data: Data) throws -> Config {
        try JSONDecoder().decode(Config.self, from: data)
    }

    /// Pretty JSON with a trailing newline: readable and diffable for people and agents.
    public func encoded() -> Data { JSON.pretty(self) }

    public var historyEnabled: Bool { history?.enabled ?? true }

    public var defaultDestination: Destination { Destination(browser: browser, profile: defaultProfile) }

    /// The browser a rule opens: its own, or the default.
    public func browser(of rule: Rule) -> String { rule.browser ?? browser }

    public func destination(of rule: Rule) -> Destination {
        Destination(browser: browser(of: rule), profile: rule.profile)
    }

    /// Every browser the config names, sorted, without duplicates.
    public var browsers: [String] {
        Array(Set([browser] + rules.compactMap(\.browser)).filter { !$0.isEmpty }).sorted()
    }

    public func index(of id: RuleID) -> Int? { rules.firstIndex { $0.id == id } }
}
