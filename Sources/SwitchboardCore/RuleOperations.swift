import Foundation

// Reading and changing rules, shared by every CLI command and the app. Validation matches the
// editor: profiles resolve within their destination's browser, directory identifiers win over
// display names, and ambiguous names are refused. Edits change only what they name. The changes
// themselves are in RuleChanges.swift.

public enum ProfileStatus: String, Codable, Sendable {
    case ok, missing, ambiguous
    /// The browser isn't installed, or its profiles couldn't be read.
    case unavailable
}

public struct DestinationInfo: Equatable, Encodable, Sendable {
    public var browser: String
    public var browserName: String
    /// The directory identifier when the saved profile resolves, otherwise the saved value.
    public var profile: String
    public var profileName: String?

    /// `Google Chrome · Work (Profile 2)`.
    public var label: String {
        profileName.map { "\(browserName) · \($0) (\(profile))" } ?? "\(browserName) · \(profile)"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(browser, forKey: AnyKey("browser"))
        try c.encode(browserName, forKey: AnyKey("browserName"))
        try c.encode(profile, forKey: AnyKey("profile"))
        try c.encode(profileName, forKey: AnyKey("profileName"))
    }
}

public struct RuleRef: Equatable, Encodable, Sendable {
    /// 1-based.
    public var index: Int
    public var condition: Condition
    public var value: String

    public var describe: String { "\(condition.rawValue) \(value)" }
}

public struct RuleInfo: Equatable, Encodable, Sendable {
    public var index: Int
    public var condition: Condition
    public var value: String
    /// `nil` when the rule inherits the default browser.
    public var browser: String?
    public var profile: String
    public var destination: DestinationInfo
    public var profileStatus: ProfileStatus
    /// The earlier rule (1-based) that always matches first, if this rule can never match.
    public var shadowedBy: Int?

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(index, forKey: AnyKey("index"))
        try c.encode(condition, forKey: AnyKey("condition"))
        try c.encode(value, forKey: AnyKey("value"))
        try c.encode(browser, forKey: AnyKey("browser"))
        try c.encode(profile, forKey: AnyKey("profile"))
        try c.encode(destination, forKey: AnyKey("destination"))
        try c.encode(profileStatus, forKey: AnyKey("profileStatus"))
        try c.encode(shadowedBy, forKey: AnyKey("shadowedBy"))
    }
}

public struct DecisionInfo: Equatable, Encodable, Sendable {
    public var rule: RuleRef?
    public var destination: DestinationInfo
    public var profileStatus: ProfileStatus

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(rule, forKey: AnyKey("rule"))
        try c.encode(destination, forKey: AnyKey("destination"))
        try c.encode(profileStatus, forKey: AnyKey("profileStatus"))
    }
}

public struct Explanation: Equatable, Sendable {
    public var decision: DecisionInfo
    /// Later rules that also match but are never reached.
    public var alsoMatches: [RuleRef]
}

public struct HistoryChange: Sendable {
    public var entry: History.Entry
    public var before: DecisionInfo
    public var after: DecisionInfo
}

/// Profile lists read once per browser, shared by the operations on edited copies of a config.
final class ProfileCache: @unchecked Sendable {
    private let lock = NSLock()
    private var lists: [String: Result<[Profile], ProfileError>] = [:]

    func profiles(_ browser: String, _ browsers: Browsers) -> Result<[Profile], ProfileError> {
        lock.lock()
        defer { lock.unlock() }
        if let found = lists[browser] { return found }
        let found = Result { () throws(ProfileError) in try Profiles.of(browsers, browser) }
        lists[browser] = found
        return found
    }
}

/// Rule operations on one config. Profile lists are read once per browser.
public struct RuleOperations: Sendable {
    public var config: Config
    public var browsers: Browsers
    public var home: Home
    let cache: ProfileCache

    public init(config: Config, browsers: Browsers, home: Home) {
        self.config = config
        self.browsers = browsers
        self.home = home
        cache = ProfileCache()
    }

    /// The same lookups on an edited config, sharing the profile cache.
    public func with(_ config: Config) -> RuleOperations {
        var copy = self
        copy.config = config
        return copy
    }

    // MARK: Profiles

    public func profiles(_ browser: String) throws(ProfileError) -> [Profile] {
        try cache.profiles(browser, browsers).get()
    }

    /// How a saved profile resolves: a directory, then an unambiguous legacy display name.
    public func resolveSaved(_ profile: String, in browser: String) -> (
        directory: String?, status: ProfileStatus
    ) {
        guard let available = try? profiles(browser) else { return (nil, .unavailable) }
        do {
            return (try Profiles.directory(profile, in: available), .ok)
        } catch .ambiguous {
            return (nil, .ambiguous)
        } catch {
            return (nil, .missing)
        }
    }

    public func describe(_ destination: Destination) -> (info: DestinationInfo, status: ProfileStatus) {
        let (directory, status) = resolveSaved(destination.profile, in: destination.browser)
        let name = directory.flatMap { d in
            (try? profiles(destination.browser))?.first { $0.directory == d }?.name
        }
        let info = DestinationInfo(
            browser: destination.browser, browserName: browserName(destination.browser),
            profile: directory ?? destination.profile, profileName: name)
        return (info, status)
    }

    public func browserName(_ browser: String) -> String {
        browser.isEmpty ? "No browser" : browsers.displayName(browser)
    }

    /// Destinations compare by standardized browser and resolved profile directory.
    public func key(_ destination: Destination) -> Destination {
        Destination(
            browser: browsers.standardize(destination.browser),
            profile: resolveSaved(destination.profile, in: destination.browser).directory
                ?? destination.profile)
    }

    // MARK: Reading

    public func rules() -> [RuleInfo] {
        var shadowed: [Int: Int] = [:]
        for u in Shadowing.unreachable(config.rules) where shadowed[u.rule] == nil { shadowed[u.rule] = u.by }
        return config.rules.enumerated().map { i, rule in
            let (destination, status) = describe(config.destination(of: rule))
            return RuleInfo(
                index: i + 1, condition: rule.condition, value: rule.value, browser: rule.browser,
                profile: rule.profile, destination: destination, profileStatus: status,
                shadowedBy: shadowed[i].map { $0 + 1 })
        }
    }

    public func reference(_ index: Int) -> RuleRef {
        let rule = config.rules[index]
        return RuleRef(index: index + 1, condition: rule.condition, value: rule.value)
    }

    public func decision(_ link: String) -> DecisionInfo {
        let decision = Router.decide(config, link: link)
        let (destination, status) = describe(decision.destination)
        return DecisionInfo(
            rule: decision.rule.map(reference), destination: destination, profileStatus: status)
    }

    public func explain(_ link: String) -> Explanation {
        let matched = Router.decide(config, link: link).rule
        let also = matched.map { m in
            ((m + 1)..<config.rules.count).filter { Router.matches(config.rules[$0], link: link) }.map(
                reference)
        }
        return Explanation(decision: decision(link), alsoMatches: also ?? [])
    }

    /// Links from history that would open somewhere else with `edited`. Each link is checked once.
    public func historyChanges(_ edited: Config, entries: [History.Entry]) -> [HistoryChange] {
        let after = with(edited)
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard seen.insert(entry.url).inserted else { return nil }
            let old = Router.decide(config, link: entry.url).destination
            let new = Router.decide(edited, link: entry.url).destination
            guard key(old) != key(new) else { return nil }
            return HistoryChange(entry: entry, before: decision(entry.url), after: after.decision(entry.url))
        }
    }

    // MARK: Resolving names

    public func knownBrowsers() -> [BrowserInfo] { browsers.known(config.browsers) }

    public static func browserCandidate(_ info: BrowserInfo) -> Candidate {
        Candidate(browser: info.locator, browserName: info.name, browserID: info.id)
    }

    /// A path, then a bundle identifier, then a name or alias, ignoring case.
    public func resolveBrowser(_ query: String) throws(OperationError) -> BrowserInfo {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = knownBrowsers()
        let candidates = known.map(Self.browserCandidate)
        if query.contains("/") || query.hasPrefix("~") {
            guard let info = browsers.at(home.expand(query).path) else {
                throw OperationError(
                    .browserNotFound,
                    "“\(query)” isn’t a supported browser. Choose one of the installed browsers.",
                    candidates: candidates)
            }
            return info
        }
        let byID = known.filter { ASCII.equalIgnoringCase($0.id, query) }
        if byID.count == 1 { return byID[0] }
        let name = ASCII.removingSuffixIgnoringCase(query, ".app")
        let found = byID.isEmpty ? known.filter { $0.answers(to: name) } : byID
        switch found.count {
        case 1: return found[0]
        case 0:
            throw OperationError(
                .browserNotFound, "No installed browser matches “\(query)”. Use a name, id, or path.",
                candidates: candidates)
        default:
            throw OperationError(
                .ambiguousBrowser, "“\(query)” matches \(found.count) browsers. Use its path.",
                candidates: found.map(Self.browserCandidate))
        }
    }

    /// A directory identifier, then a display name, then either ignoring case; only when one
    /// profile matches.
    public func resolveProfile(_ query: String, in browser: String) throws(OperationError) -> Profile {
        let browserName = browserName(browser)
        let available: [Profile]
        do {
            available = try profiles(browser)
        } catch .browserUnavailable {
            throw OperationError(
                .browserNotFound,
                "\(browserName) isn’t installed at \(browser), so its profiles can’t be listed.",
                candidates: knownBrowsers().map(Self.browserCandidate))
        } catch {
            throw OperationError(.profilesUnreadable, "\(browserName)’s profiles couldn’t be read. \(error)")
        }
        if let exact = available.first(where: { $0.directory == query }) { return exact }
        let named = available.filter { $0.name == query }
        let found =
            named.isEmpty
            ? available.filter {
                ASCII.equalIgnoringCase($0.name, query) || ASCII.equalIgnoringCase($0.directory, query)
            }
            : named
        if found.count == 1 { return found[0] }
        let candidates = (found.isEmpty ? available : found).map {
            Candidate(browser: browser, browserName: browserName, profile: $0.directory, profileName: $0.name)
        }
        if found.isEmpty {
            throw OperationError(
                .profileNotFound, "No profile “\(query)” in \(browserName).", candidates: candidates)
        }
        throw OperationError(
            .ambiguousProfile, "“\(query)” matches \(found.count) profiles in \(browserName).",
            candidates: candidates)
    }

    public func ruleCandidates() -> [Candidate] {
        config.rules.enumerated().map { RuleOperations.ruleCandidate($0, $1) }
    }

    /// The 0-based index of 1-based `position`.
    public func ruleIndex(_ position: Int) throws(OperationError) -> Int {
        let count = config.rules.count
        guard position >= 1, position <= count else {
            let message =
                count == 0
                ? "There are no rules." : "There is no rule \(position). Rules are numbered 1–\(count)."
            throw OperationError(.ruleNotFound, message, candidates: ruleCandidates())
        }
        return position - 1
    }

    static func ruleCandidate(_ index: Int, _ rule: Rule) -> Candidate {
        Candidate(index: index + 1, condition: rule.condition, value: rule.value)
    }
}

/// ASCII-only case folding, as the Rust rewrite's `eq_ignore_ascii_case`.
enum ASCII {
    static func lower(_ text: String) -> [UInt8] {
        text.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }
    }

    static func equalIgnoringCase(_ a: String, _ b: String) -> Bool { lower(a) == lower(b) }

    static func removingSuffixIgnoringCase(_ text: String, _ suffix: String) -> String {
        let (t, s) = (Array(text.utf8), lower(suffix))
        guard t.count >= s.count, lower(String(decoding: t.suffix(s.count), as: UTF8.self)) == s else {
            return text
        }
        return String(decoding: t.dropLast(s.count), as: UTF8.self)
    }
}
