import Foundation

// The rule edits behind `route`, `rules update|move|remove` and `default`. Each returns the edited
// config without saving it; the caller saves through ConfigStore. Nothing is changed silently:
// a change that wouldn't do what was asked, or would hide other rules, is refused.

public struct RouteRequest: Sendable {
    public var url: String
    public var profile: String
    public var browser: String?
    public var condition: Condition
    public var value: String?
    public var allowShadowing: Bool

    public init(
        url: String, profile: String, browser: String? = nil, condition: Condition = .domain,
        value: String? = nil,
        allowShadowing: Bool = false
    ) {
        self.url = url
        self.profile = profile
        self.browser = browser
        self.condition = condition
        self.value = value
        self.allowShadowing = allowShadowing
    }
}

public enum BrowserChoice: Equatable, Sendable {
    case `default`
    case browser(String)
}

public struct RuleUpdate: Sendable {
    public var profile: String?
    public var browser: BrowserChoice?
    public var condition: Condition?
    public var value: String?
    public var allowShadowing: Bool

    public init(
        profile: String? = nil, browser: BrowserChoice? = nil, condition: Condition? = nil,
        value: String? = nil,
        allowShadowing: Bool = false
    ) {
        self.profile = profile
        self.browser = browser
        self.condition = condition
        self.value = value
        self.allowShadowing = allowShadowing
    }
}

public enum Action: String, Codable, Sendable { case added, updated, moved, removed, unchanged }

public struct RuleChange: Sendable {
    public var config: Config
    public var action: Action
    /// 0-based position of the affected rule in `config`, or in the original for a removal.
    public var index: Int?
    /// Rules that can no longer match because of this change.
    public var unreachable: [Unreachable]

    public var changed: Bool { action != .unchanged }
}

public struct DefaultChange: Sendable {
    public var config: Config
    public var changed: Bool
}

extension RuleOperations {
    /// Makes `request.url` open at the requested destination: updates a rule with the same
    /// condition and pattern, or inserts one just before the rule that matches now (so only links
    /// that matched it can change), or appends one.
    public func route(_ request: RouteRequest) throws(OperationError) -> RuleChange {
        let value = try Self.ruleValue(request)
        let (overrideBrowser, target) = try self.target(request.browser, request.profile)
        let current = Router.decide(config, link: request.url)
        if key(current.destination) == key(target) {
            return RuleChange(config: config, action: .unchanged, index: current.rule, unreachable: [])
        }
        var edited = config
        let lowered = Array(value.lowercased().utf8)
        let index: Int
        let action: Action
        if let existing = config.rules.firstIndex(where: {
            $0.condition == request.condition && Array($0.value.lowercased().utf8) == lowered
        }) {
            edited.rules[existing].browser = overrideBrowser
            edited.rules[existing].profile = target.profile
            (index, action) = (existing, .updated)
        } else {
            let at = current.rule ?? config.rules.count
            edited.rules.insert(
                Rule(request.condition, value, profile: target.profile, browser: overrideBrowser), at: at)
            (index, action) = (at, .added)
        }
        // Verify first: a rule that doesn't route the link as asked matters more than what it hides.
        let after = Router.decide(edited, link: request.url)
        if key(after.destination) != key(target) {
            let reached = with(edited).decision(request.url)
            let via = reached.rule.map { "rule \($0.index) (\($0.describe))" } ?? "the default"
            throw OperationError(
                .verificationFailed,
                "After the change the link would still open in \(reached.destination.label) through \(via). Nothing was written."
            )
        }
        let unreachable = try checkShadowing(edited, index, allowed: request.allowShadowing)
        return RuleChange(config: edited, action: action, index: index, unreachable: unreachable)
    }

    public func updateRule(_ position: Int, _ update: RuleUpdate) throws(OperationError) -> RuleChange {
        let index = try ruleIndex(position)
        if update.profile == nil && update.browser == nil && update.condition == nil && update.value == nil {
            throw .invalid(
                "Pass at least one of --profile, --browser, --default-browser, --match, or --value.")
        }
        if update.browser != nil && update.profile == nil {
            throw .invalid(
                "Changing a rule’s browser needs --profile: profile identifiers belong to one browser.")
        }
        var rule = config.rules[index]
        switch update.browser {
        case .browser(let query): rule.browser = try resolveBrowser(query).locator
        case .default: rule.browser = nil
        case nil: break
        }
        if let profile = update.profile {
            rule.profile = try resolveProfile(profile, in: config.browser(of: rule)).directory
        }
        if let condition = update.condition { rule.condition = condition }
        if let value = update.value { rule.value = try Self.pattern(value) }
        if rule.condition == .domain && (update.condition != nil || update.value != nil) {
            try Self.validateDomain(rule.value)
        }
        var edited = config
        edited.rules[index] = rule
        if edited == config {
            return RuleChange(config: edited, action: .unchanged, index: index, unreachable: [])
        }
        let unreachable = try checkShadowing(edited, index, allowed: update.allowShadowing)
        return RuleChange(config: edited, action: .updated, index: index, unreachable: unreachable)
    }

    public func moveRule(from: Int, to: Int) throws(OperationError) -> RuleChange {
        let source = try ruleIndex(from)
        let destination = try ruleIndex(to)
        if source == destination {
            return RuleChange(config: config, action: .unchanged, index: source, unreachable: [])
        }
        var edited = config
        let rule = edited.rules.remove(at: source)
        edited.rules.insert(rule, at: destination)
        let unreachable = Shadowing.newlyUnreachable(before: config.rules, after: edited.rules)
        return RuleChange(config: edited, action: .moved, index: destination, unreachable: unreachable)
    }

    public func removeRule(_ position: Int) throws(OperationError) -> RuleChange {
        let index = try ruleIndex(position)
        var edited = config
        edited.rules.remove(at: index)
        return RuleChange(config: edited, action: .removed, index: index, unreachable: [])
    }

    /// Changes the default destination. Rules that inherit the default browser chose their profile
    /// in it, and the same directory can be a different person in another browser, so changing the
    /// default browser is refused while any rule inherits it. Nothing is cleared silently.
    public func setDefault(browser: String?, profile: String?) throws(OperationError) -> DefaultChange {
        var edited = config
        if let query = browser {
            let info = try resolveBrowser(query)
            if info.locator != browsers.standardize(config.browser) {
                guard profile != nil else {
                    throw .invalid(
                        "Changing the default browser needs --profile: profile identifiers belong to one browser."
                    )
                }
                let inheriting = config.rules.indices.filter { config.rules[$0].browser == nil }
                if !inheriting.isEmpty && !config.browser.isEmpty {
                    throw inheritingRules(inheriting)
                }
                edited.browser = info.locator
            }
        }
        if let profile {
            edited.defaultProfile = try resolveProfile(profile, in: edited.browser).directory
        }
        return DefaultChange(config: edited, changed: edited != config)
    }

    private func inheritingRules(_ inheriting: [Int]) -> OperationError {
        let one = inheriting.count == 1
        let numbers = inheriting.map { String($0 + 1) }
        let message =
            "\(one ? "Rule" : "Rules") \(Self.list(numbers)) \(one ? "uses" : "use") the default browser. Give \(one ? "it" : "each one") an explicit browser and profile with `rules update` first."
        let candidates = inheriting.map { i in
            let rule = config.rules[i]
            let directory = resolveSaved(rule.profile, in: config.browser).directory ?? rule.profile
            var candidate = Self.ruleCandidate(i, rule)
            candidate.browser = config.browser
            candidate.profile = directory
            candidate.suggestion =
                "\(Identity.cliName) rules update \(i + 1) --browser \(Self.quoted(config.browser)) --profile \(Self.quoted(directory))"
            return candidate
        }
        return OperationError(.inheritingRules, message, candidates: candidates)
    }

    /// Without a browser, the rule inherits the default browser and the profile resolves there.
    private func target(_ browser: String?, _ profile: String) throws(OperationError) -> (
        String?, Destination
    ) {
        guard let query = browser else {
            let directory = try resolveProfile(profile, in: config.browser).directory
            return (nil, Destination(browser: config.browser, profile: directory))
        }
        let info = try resolveBrowser(query)
        let directory = try resolveProfile(profile, in: info.locator).directory
        return (info.locator, Destination(browser: info.locator, profile: directory))
    }

    /// The changed rule must stay reachable; rules it would hide need permission.
    private func checkShadowing(_ edited: Config, _ index: Int, allowed: Bool) throws(OperationError)
        -> [Unreachable]
    {
        let unreachable = Shadowing.newlyUnreachable(before: config.rules, after: edited.rules)
        let after = with(edited)
        if let own = unreachable.first(where: { $0.rule == index }) {
            throw OperationError(
                .verificationFailed,
                "Rule \(index + 1) would never match: rule \(own.by + 1) (\(after.reference(own.by).describe)) always matches first. Nothing was written.",
                candidates: [Self.ruleCandidate(own.by, edited.rules[own.by])])
        }
        if !allowed && !unreachable.isEmpty {
            let hidden = unreachable.map { "rule \($0.rule + 1) (\(after.reference($0.rule).describe))" }
            throw OperationError(
                .wouldShadow,
                "Rule \(index + 1) (\(after.reference(index).describe)) would stop \(Self.list(hidden)) from ever matching. Use a narrower --value, or pass --allow-shadowing.",
                candidates: unreachable.map { Self.ruleCandidate($0.rule, edited.rules[$0.rule]) })
        }
        return unreachable
    }

    static func ruleValue(_ request: RouteRequest) throws(OperationError) -> String {
        if let value = request.value {
            let value = try pattern(value)
            if request.condition == .domain { try validateDomain(value) }
            return value
        }
        switch request.condition {
        case .domain:
            guard let host = Link.webHost(request.url) else {
                throw .invalid(
                    "Domain rules only match web links. Use --match exact, or --match contains with --value.")
            }
            return host
        case .exact: return request.url
        case .contains: throw .invalid("--match contains needs --value, the text the link must contain.")
        }
    }

    /// A trimmed, non-empty pattern.
    public static func pattern(_ value: String) throws(OperationError) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw .invalid("--value can’t be empty: empty patterns never match.") }
        return trimmed
    }

    public static func validateDomain(_ value: String) throws(OperationError) {
        if value.contains("/") || value.unicodeScalars.contains(where: \.properties.isWhitespace) {
            throw .invalid(
                "“\(value)” isn’t a domain. Domain rules take a host such as github.com, which also matches its subdomains."
            )
        }
    }

    /// "a", "a and b", "a, b, and c".
    public static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: "\(items.dropLast().joined(separator: ", ")), and \(items[items.count - 1])"
        }
    }

    /// Quotes `value` for a POSIX shell when it needs it.
    public static func quoted(_ value: String) -> String {
        if !value.isEmpty
            && value.unicodeScalars.allSatisfy({
                $0.properties.isAlphabetic || $0.properties.numericType != nil
                    || "/._-".unicodeScalars.contains($0)
            })
        {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
