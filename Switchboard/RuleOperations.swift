import Foundation

enum ProfileStatus: String, Encodable {
    case ok, missing, ambiguous
    // The browser isn't installed, or its profiles couldn't be read.
    case unavailable
}

struct DestinationInfo: Encodable, Equatable {
    var browser: String
    var browserName: String
    // The directory identifier when the saved profile resolves, otherwise the saved value.
    var profile: String
    var profileName: String?

    enum CodingKeys: String, CodingKey { case browser, browserName, profile, profileName }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(browser, forKey: .browser)
        try container.encode(browserName, forKey: .browserName)
        try container.encode(profile, forKey: .profile)
        try container.encode(profileName, forKey: .profileName)
    }
}

struct RuleReference: Encodable, Equatable {
    var index: Int  // 1-based
    var condition: Condition
    var value: String
}

struct RuleInfo: Encodable, Equatable {
    var index: Int
    var condition: Condition
    var value: String
    // nil when the rule inherits the default browser.
    var browser: String?
    var profile: String
    var destination: DestinationInfo
    var profileStatus: ProfileStatus
    // The earlier rule that always matches first, if this rule can never match.
    var shadowedBy: Int?

    var reference: RuleReference { RuleReference(index: index, condition: condition, value: value) }

    enum CodingKeys: String, CodingKey {
        case index, condition, value, browser, profile, destination, profileStatus, shadowedBy
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(condition, forKey: .condition)
        try container.encode(value, forKey: .value)
        try container.encode(browser, forKey: .browser)
        try container.encode(profile, forKey: .profile)
        try container.encode(destination, forKey: .destination)
        try container.encode(profileStatus, forKey: .profileStatus)
        try container.encode(shadowedBy, forKey: .shadowedBy)
    }
}

// Where a URL goes: a rule (nil for the default destination) and the browser/profile it chooses.
struct DecisionInfo: Encodable, Equatable {
    var rule: RuleReference?
    var destination: DestinationInfo
    var profileStatus: ProfileStatus

    enum CodingKeys: String, CodingKey { case rule, destination, profileStatus }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rule, forKey: .rule)
        try container.encode(destination, forKey: .destination)
        try container.encode(profileStatus, forKey: .profileStatus)
    }
}

struct Explanation: Equatable {
    var decision: DecisionInfo
    // Later rules that also match the URL but are never reached.
    var alsoMatches: [RuleReference]
}

struct HistoryChange {
    var entry: HistoryEntry
    var before: DecisionInfo
    var after: DecisionInfo
}

struct RouteRequest {
    var url: URL
    var profile: String
    var browser: String? = nil
    var condition: Condition = .domain
    var value: String? = nil
    var allowShadowing = false
}

struct RuleUpdate {
    enum BrowserChoice: Equatable {
        case defaultBrowser
        case browser(String)
    }

    var profile: String? = nil
    var browser: BrowserChoice? = nil
    var condition: Condition? = nil
    var value: String? = nil
    var allowShadowing = false
}

struct RuleChange {
    enum Action: String, Encodable { case added, updated, moved, removed, unchanged }

    var config: Config
    var action: Action
    // 0-based position of the affected rule in `config`, or in the original configuration for a removal.
    var index: Int?
    // Rules that can no longer match because of this change.
    var unreachable: [Shadowing.Unreachable] = []

    var changed: Bool { action != .unchanged }
}

struct DefaultChange {
    var config: Config
    var changed: Bool
}

// Shared by every CLI command that reads or changes rules. Validation matches the editor: profiles are
// resolved within the destination's browser, directory identifiers win over display names, and ambiguous
// names are refused. Edits change only the rules they name.
struct RuleOperations {
    let config: Config
    let profiles: ProfileLookup

    var catalog: BrowserCatalog { profiles.catalog }

    init(config: Config, catalog: BrowserCatalog) {
        self.init(config: config, profiles: ProfileLookup(catalog: catalog))
    }

    init(config: Config, profiles: ProfileLookup) {
        self.config = config
        self.profiles = profiles
    }

    // MARK: Reading

    func describe(_ destination: Destination) -> (info: DestinationInfo, status: ProfileStatus) {
        let resolution = profiles.resolve(saved: destination.profile, in: destination.browser)
        let directory = resolution.directory ?? destination.profile
        let name = resolution.directory == nil ? nil : profiles.name(of: directory, in: destination.browser)
        return (
            DestinationInfo(
                browser: destination.browser, browserName: BrowserInfo.displayName(path: destination.browser),
                profile: directory, profileName: name),
            resolution.status
        )
    }

    var defaultDestination: Destination {
        Destination(browser: config.browser, profile: config.defaultProfile)
    }

    func rules() -> [RuleInfo] {
        let shadowed = Dictionary(
            Shadowing.unreachable(config.routes).map { ($0.rule, $0.by) },
            uniquingKeysWith: { first, _ in first })
        return config.routes.enumerated().map { index, route in
            let described = describe(
                Destination(browser: route.browser ?? config.browser, profile: route.profile))
            return RuleInfo(
                index: index + 1, condition: route.condition, value: route.value, browser: route.browser,
                profile: route.profile, destination: described.info, profileStatus: described.status,
                shadowedBy: shadowed[index].map { $0 + 1 })
        }
    }

    func rule(at index: Int) -> RuleInfo { rules()[index] }

    func decision(for url: URL) -> DecisionInfo {
        let decision = Router(config: config).decision(url: url)
        let described = describe(decision.destination)
        return DecisionInfo(
            rule: decision.route.flatMap(reference(for:)), destination: described.info,
            profileStatus: described.status)
    }

    func explain(_ url: URL) -> Explanation {
        let decision = Router(config: config).decision(url: url)
        let matched = decision.route.flatMap { route in config.routes.firstIndex { $0.id == route.id } }
        let later = matched.map { index in config.routes.indices.filter { $0 > index } } ?? []
        return Explanation(
            decision: self.decision(for: url),
            alsoMatches: later.filter { Router.matches(config.routes[$0], url: url) }.map(reference(at:)))
    }

    func reference(at index: Int) -> RuleReference {
        let route = config.routes[index]
        return RuleReference(index: index + 1, condition: route.condition, value: route.value)
    }

    private func reference(for route: Route) -> RuleReference? {
        config.routes.firstIndex { $0.id == route.id }.map(reference(at:))
    }

    // URLs from history whose destination would change with `edited`. Each URL is checked once.
    func historyChanges(to edited: Config, entries: [HistoryEntry]) -> [HistoryChange] {
        let after = RuleOperations(config: edited, profiles: profiles)
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard seen.insert(entry.url).inserted, let url = URL(string: entry.url) else { return nil }
            let old = Router(config: config).decision(url: url).destination
            let new = Router(config: edited).decision(url: url).destination
            guard key(old) != key(new) else { return nil }
            return HistoryChange(entry: entry, before: decision(for: url), after: after.decision(for: url))
        }
    }

    // MARK: Resolving names

    func browsers() -> [BrowserInfo] { catalog.browsers(including: Array(config.browserPaths)) }

    // An app path, then a bundle identifier, then a case-insensitive display name.
    func resolveBrowser(_ query: String) throws -> BrowserInfo {
        let query = query.trimmingCharacters(in: .whitespaces)
        let known = browsers()
        if query.contains("/") || query.hasPrefix("~") {
            let home = catalog.profileStore.homeDirectory.path
            let path = query.hasPrefix("~") ? home + query.dropFirst() : query
            if let info = BrowserInfo(path: path) { return info }
            throw OperationError(
                code: .browserNotFound,
                message:
                    "“\(query)” isn’t a supported Chromium browser. Choose one of the installed browsers.",
                candidates: known.map(Self.candidate))
        }
        let lowered = query.lowercased()
        let byIdentifier = known.filter { $0.bundleIdentifier.lowercased() == lowered }
        if byIdentifier.count == 1 { return byIdentifier[0] }
        let name = lowered.hasSuffix(".app") ? String(lowered.dropLast(4)) : lowered
        let byName =
            byIdentifier.isEmpty
            ? known.filter { ([$0.name] + $0.alternateNames).contains { $0.lowercased() == name } }
            : byIdentifier
        if byName.count == 1 { return byName[0] }
        if byName.isEmpty {
            throw OperationError(
                code: .browserNotFound,
                message:
                    "No installed browser matches “\(query)”. Use a name, bundle identifier, or app path.",
                candidates: known.map(Self.candidate))
        }
        throw OperationError(
            code: .ambiguousBrowser,
            message: "“\(query)” matches \(byName.count) browsers. Use its app path.",
            candidates: byName.map(Self.candidate))
    }

    // A directory identifier, then a display name, accepted only when unambiguous.
    func resolveProfile(_ query: String, browser: String) throws -> Profile {
        let browserName = BrowserInfo.displayName(path: browser)
        let available: [Profile]
        do {
            available = try profiles.profiles(in: browser)
        } catch ProfileError.browserUnavailable {
            throw OperationError(
                code: .browserNotFound,
                message: "\(browserName) isn’t installed at \(browser), so its profiles can’t be listed.",
                candidates: browsers().map(Self.candidate))
        } catch {
            throw OperationError(
                code: .profilesUnreadable,
                message: "\(browserName)’s profiles couldn’t be read. \(error.localizedDescription)")
        }
        if let directory = available.first(where: { $0.directory == query }) { return directory }
        let named = available.filter { $0.name == query }
        let loose =
            named.isEmpty
            ? available.filter {
                $0.name.lowercased() == query.lowercased() || $0.directory.lowercased() == query.lowercased()
            }
            : named
        if loose.count == 1 { return loose[0] }
        let candidates = (loose.isEmpty ? available : loose).map {
            Candidate(browser: browser, browserName: browserName, profile: $0.directory, profileName: $0.name)
        }
        if loose.isEmpty {
            throw OperationError(
                code: .profileNotFound, message: "No profile “\(query)” in \(browserName).",
                candidates: candidates)
        }
        throw OperationError(
            code: .ambiguousProfile, message: "“\(query)” matches \(loose.count) profiles in \(browserName).",
            candidates: candidates)
    }

    static func candidate(_ browser: BrowserInfo) -> Candidate {
        Candidate(
            browser: browser.path, browserName: browser.name, bundleIdentifier: browser.bundleIdentifier)
    }

    func ruleCandidates() -> [Candidate] {
        config.routes.indices.map {
            Candidate(index: $0 + 1, condition: config.routes[$0].condition, value: config.routes[$0].value)
        }
    }

    // MARK: Changing rules

    func route(_ request: RouteRequest) throws -> RuleChange {
        let value = try ruleValue(request)
        let target = try target(browser: request.browser, profile: request.profile)
        let current = Router(config: config).decision(url: request.url)
        if key(current.destination) == key(target.destination) {
            let index = current.route.flatMap { route in config.routes.firstIndex { $0.id == route.id } }
            return RuleChange(config: config, action: .unchanged, index: index)
        }
        var edited = config
        let index: Int
        let action: RuleChange.Action
        if let existing = config.routes.firstIndex(where: {
            $0.condition == request.condition && $0.value.lowercased() == value.lowercased()
        }) {
            index = existing
            action = .updated
            edited.routes[index].browser = target.override
            edited.routes[index].profile = target.destination.profile
        } else {
            // Immediately before the rule that matches now, so only URLs that matched it can change.
            index =
                current.route.flatMap { route in config.routes.firstIndex { $0.id == route.id } }
                ?? config.routes.count
            action = .added
            edited.routes.insert(
                Route(
                    condition: request.condition, value: value, profile: target.destination.profile,
                    browser: target.override), at: index)
        }
        // Verify first: a rule that doesn't route the URL as asked matters more than what it would hide.
        let after = Router(config: edited).decision(url: request.url)
        guard key(after.destination) == key(target.destination) else {
            let operations = RuleOperations(config: edited, profiles: profiles)
            let reached = operations.decision(for: request.url)
            let via =
                reached.rule.map { "rule \($0.index) (\($0.condition.rawValue) \($0.value))" }
                ?? "the default"
            throw OperationError(
                code: .verificationFailed,
                message:
                    "After the change the URL would still open in \(Self.label(reached.destination)) through \(via). Nothing was written."
            )
        }
        let unreachable = try checkShadowing(edited, index: index, allowed: request.allowShadowing)
        return RuleChange(config: edited, action: action, index: index, unreachable: unreachable)
    }

    func updateRule(at position: Int, _ update: RuleUpdate) throws -> RuleChange {
        let index = try ruleIndex(position)
        guard update.profile != nil || update.browser != nil || update.condition != nil || update.value != nil
        else {
            throw OperationError.invalidArgument(
                "Pass at least one of --profile, --browser, --default-browser, --match, or --value.")
        }
        guard update.browser == nil || update.profile != nil else {
            throw OperationError.invalidArgument(
                "Changing a rule’s browser needs --profile: profile identifiers belong to one browser.")
        }
        var rule = config.routes[index]
        switch update.browser {
        case .browser(let query): rule.browser = try resolveBrowser(query).path
        case .defaultBrowser: rule.browser = nil
        case nil: break
        }
        if let profile = update.profile {
            rule.profile = try resolveProfile(profile, browser: rule.browser ?? config.browser).directory
        }
        if let condition = update.condition { rule.condition = condition }
        if let value = update.value { rule.value = try Self.pattern(value) }
        if rule.condition == .domain && (update.condition != nil || update.value != nil) {
            try Self.validateDomain(rule.value)
        }
        var edited = config
        edited.routes[index] = rule
        guard edited != config else { return RuleChange(config: config, action: .unchanged, index: index) }
        let unreachable = try checkShadowing(edited, index: index, allowed: update.allowShadowing)
        return RuleChange(config: edited, action: .updated, index: index, unreachable: unreachable)
    }

    func moveRule(from: Int, to: Int) throws -> RuleChange {
        let source = try ruleIndex(from)
        let destination = try ruleIndex(to)
        guard source != destination else {
            return RuleChange(config: config, action: .unchanged, index: source)
        }
        var edited = config
        edited.routes.insert(edited.routes.remove(at: source), at: destination)
        return RuleChange(
            config: edited, action: .moved, index: destination,
            unreachable: Shadowing.newlyUnreachable(before: config.routes, after: edited.routes))
    }

    func removeRule(at position: Int) throws -> RuleChange {
        let index = try ruleIndex(position)
        var edited = config
        edited.routes.remove(at: index)
        return RuleChange(config: edited, action: .removed, index: index)
    }

    // Changing the default browser also changes every rule that inherits it. Their profile identifiers were
    // chosen in the old browser and can name different people in the new one, so those rules need an
    // explicit browser and profile first. Unlike the editor, nothing is cleared silently.
    func setDefault(browser: String?, profile: String?) throws -> DefaultChange {
        var edited = config
        if let browser {
            let info = try resolveBrowser(browser)
            if info.path != BrowserInfo.standardized(config.browser) {
                guard profile != nil else {
                    throw OperationError.invalidArgument(
                        "Changing the default browser needs --profile: profile identifiers belong to one browser."
                    )
                }
                let inheriting = config.routes.indices.filter { config.routes[$0].browser == nil }
                if !inheriting.isEmpty {
                    throw OperationError(
                        code: .inheritingRules,
                        message:
                            "\(inheriting.count == 1 ? "Rule" : "Rules") \(Self.list(inheriting.map { "\($0 + 1)" })) \(inheriting.count == 1 ? "uses" : "use") the default browser. Give \(inheriting.count == 1 ? "it" : "each one") an explicit browser and profile with `switchboard rules update` first.",
                        candidates: inheriting.map { index in
                            let route = config.routes[index]
                            let directory = profiles.resolve(saved: route.profile, in: config.browser)
                                .directory
                            return Candidate(
                                index: index + 1, condition: route.condition, value: route.value,
                                browser: config.browser, profile: directory ?? route.profile,
                                suggestion:
                                    "switchboard rules update \(index + 1) --browser \(Self.quoted(config.browser)) --profile \(Self.quoted(directory ?? route.profile))"
                            )
                        })
                }
                edited.browser = info.path
            }
        }
        if let profile {
            edited.defaultProfile = try resolveProfile(profile, browser: edited.browser).directory
        }
        return DefaultChange(config: edited, changed: edited != config)
    }

    // MARK: Helpers

    func ruleIndex(_ position: Int) throws -> Int {
        guard config.routes.indices.contains(position - 1) else {
            throw OperationError(
                code: .ruleNotFound,
                message: config.routes.isEmpty
                    ? "There are no rules."
                    : "There is no rule \(position). Rules are numbered 1–\(config.routes.count).",
                candidates: ruleCandidates())
        }
        return position - 1
    }

    // Compares destinations by browser and resolved profile directory.
    func key(_ destination: Destination) -> Destination {
        Destination(
            browser: BrowserInfo.standardized(destination.browser),
            profile: profiles.resolve(saved: destination.profile, in: destination.browser).directory
                ?? destination.profile)
    }

    private struct Target {
        var override: String?
        var destination: Destination
    }

    // Without a browser, the rule inherits the default browser and the profile is resolved there.
    private func target(browser: String?, profile: String) throws -> Target {
        guard let browser else {
            return Target(
                override: nil,
                destination: Destination(
                    browser: config.browser,
                    profile: try resolveProfile(profile, browser: config.browser).directory))
        }
        let info = try resolveBrowser(browser)
        return Target(
            override: info.path,
            destination: Destination(
                browser: info.path, profile: try resolveProfile(profile, browser: info.path).directory))
    }

    private func ruleValue(_ request: RouteRequest) throws -> String {
        if let value = request.value {
            let pattern = try Self.pattern(value)
            if request.condition == .domain { try Self.validateDomain(pattern) }
            return pattern
        }
        switch request.condition {
        case .domain:
            guard Router.isWebURL(request.url), let host = request.url.host?.lowercased() else {
                throw OperationError.invalidArgument(
                    "Domain rules only match web links. Use --match exact, or --match contains with --value.")
            }
            return host
        case .exact:
            return request.url.absoluteString
        case .contains:
            throw OperationError.invalidArgument(
                "--match contains needs --value, the text the URL must contain.")
        }
    }

    // The changed rule itself must stay reachable; other rules it would hide need explicit permission.
    private func checkShadowing(_ edited: Config, index: Int, allowed: Bool) throws -> [Shadowing.Unreachable]
    {
        let unreachable = Shadowing.newlyUnreachable(before: config.routes, after: edited.routes)
        let after = RuleOperations(config: edited, profiles: profiles)
        if let own = unreachable.first(where: { $0.rule == index }) {
            throw OperationError(
                code: .verificationFailed,
                message:
                    "Rule \(index + 1) would never match: rule \(own.by + 1) (\(Self.describe(after.reference(at: own.by)))) always matches first. Nothing was written.",
                candidates: [after.candidate(at: own.by)])
        }
        guard allowed || unreachable.isEmpty else {
            let hidden = unreachable.map {
                "rule \($0.rule + 1) (\(Self.describe(after.reference(at: $0.rule))))"
            }
            throw OperationError(
                code: .wouldShadow,
                message:
                    "Rule \(index + 1) (\(Self.describe(after.reference(at: index)))) would stop \(Self.list(hidden)) from ever matching. Use a narrower --value, or pass --allow-shadowing.",
                candidates: unreachable.map { after.candidate(at: $0.rule) })
        }
        return unreachable
    }

    private func candidate(at index: Int) -> Candidate {
        let route = config.routes[index]
        return Candidate(index: index + 1, condition: route.condition, value: route.value)
    }

    static func pattern(_ value: String) throws -> String {
        let pattern = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            throw OperationError.invalidArgument("--value can’t be empty: empty patterns never match.")
        }
        return pattern
    }

    static func validateDomain(_ value: String) throws {
        guard !value.contains("/"), !value.contains(where: \.isWhitespace) else {
            throw OperationError.invalidArgument(
                "“\(value)” isn’t a domain. Domain rules take a host such as github.com, which also matches its subdomains."
            )
        }
    }

    static func describe(_ reference: RuleReference) -> String {
        "\(reference.condition.rawValue) \(reference.value)"
    }

    static func label(_ destination: DestinationInfo) -> String {
        guard let name = destination.profileName else {
            return "\(destination.browserName) · \(destination.profile)"
        }
        return "\(destination.browserName) · \(name) (\(destination.profile))"
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0, 1: items.first ?? ""
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }

    static func quoted(_ value: String) -> String {
        value.allSatisfy { $0.isLetter || $0.isNumber || "/._-".contains($0) }
            ? value : "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// Profile lists are read once per browser for each command.
final class ProfileLookup {
    let catalog: BrowserCatalog
    private var cache: [String: Result<[Profile], any Error>] = [:]

    init(catalog: BrowserCatalog) {
        self.catalog = catalog
    }

    func profiles(in browser: String) throws -> [Profile] {
        if let cached = cache[browser] { return try cached.get() }
        let result = Result { try catalog.profileStore.profiles(browserPath: browser) }
        cache[browser] = result
        return try result.get()
    }

    // How a saved identifier resolves with the app's rules: a directory, then an unambiguous legacy name.
    func resolve(saved profile: String, in browser: String) -> (directory: String?, status: ProfileStatus) {
        guard let available = try? profiles(in: browser) else { return (nil, .unavailable) }
        do {
            return (try BrowserProfiles.directory(for: profile, in: available), .ok)
        } catch ProfileError.ambiguous {
            return (nil, .ambiguous)
        } catch {
            return (nil, .missing)
        }
    }

    func name(of directory: String, in browser: String) -> String? {
        (try? profiles(in: browser))?.first { $0.directory == directory }?.name
    }
}

// Rules that can never match because an earlier rule matches every URL they would.
enum Shadowing {
    struct Unreachable: Equatable {
        var rule: Int  // 0-based
        var by: Int
    }

    static func covers(_ earlier: Route, _ later: Route) -> Bool {
        let first = earlier.value.lowercased()
        let second = later.value.lowercased()
        guard !first.isEmpty, !second.isEmpty else { return false }
        switch (earlier.condition, later.condition) {
        case (_, .exact):
            // An exact rule matches one URL; it is unreachable if the earlier rule matches that URL.
            return URL(string: later.value).map { Router.matches(earlier, url: $0) } ?? false
        case (.contains, .contains):
            return second.contains(first)
        case (.contains, .domain):
            // Every URL a domain rule matches contains its domain.
            return second.contains(first)
        case (.domain, .domain):
            return second == first || second.hasSuffix("." + first)
        case (.domain, .contains), (.exact, .contains), (.exact, .domain):
            return false
        }
    }

    static func unreachable(_ routes: [Route]) -> [Unreachable] {
        routes.indices.compactMap { later in
            routes[..<later].firstIndex { covers($0, routes[later]) }.map { Unreachable(rule: later, by: $0) }
        }
    }

    static func newlyUnreachable(before: [Route], after: [Route]) -> [Unreachable] {
        let existing = Set(unreachable(before).map { before[$0.rule].id })
        return unreachable(after).filter { !existing.contains(after[$0.rule].id) }
    }
}
