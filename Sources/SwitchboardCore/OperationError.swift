// Failures with a stable code and exit status, shared by the CLI's text and JSON output.
// Not-found and ambiguous failures list the candidates to choose from and never change anything.

public enum Code: String, Codable, Sendable {
    case invalidArgument = "invalid_argument"
    case wouldShadow = "would_shadow"
    case verificationFailed = "verification_failed"
    case historyDisabled = "history_disabled"
    case historyUnreadable = "history_unreadable"
    case profilesUnreadable = "profiles_unreadable"
    case writeFailed = "write_failed"
    case profileNotFound = "profile_not_found"
    case ambiguousProfile = "ambiguous_profile"
    case browserNotFound = "browser_not_found"
    case ambiguousBrowser = "ambiguous_browser"
    case ruleNotFound = "rule_not_found"
    case historyEntryNotFound = "history_entry_not_found"
    case ambiguousHistoryEntry = "ambiguous_history_entry"
    case inheritingRules = "inheriting_rules"
    case agentNotFound = "agent_not_found"
    case configUnreadable = "config_unreadable"
    case configInvalid = "config_invalid"
    case conflict

    /// 1 failed, 2 bad command line, 3 not found or ambiguous, 4 config unreadable or invalid,
    /// 5 conflict.
    public var exitCode: Int32 {
        switch self {
        case .invalidArgument: 2
        case .profileNotFound, .ambiguousProfile, .browserNotFound, .ambiguousBrowser, .ruleNotFound,
            .historyEntryNotFound, .ambiguousHistoryEntry, .inheritingRules, .agentNotFound:
            3
        case .configUnreadable, .configInvalid: 4
        case .conflict: 5
        case .wouldShadow, .verificationFailed, .historyDisabled, .historyUnreadable, .profilesUnreadable,
            .writeFailed:
            1
        }
    }
}

/// One choice in a not-found or ambiguous answer. Only the fields that apply are present.
public struct Candidate: Codable, Equatable, Sendable {
    public var index: Int?
    public var condition: Condition?
    public var value: String?
    public var browser: String?
    public var browserName: String?
    public var browserID: String?
    public var profile: String?
    public var profileName: String?
    public var id: String?
    public var time: String?
    public var url: String?
    public var agent: String?
    /// A command that resolves the problem for this candidate.
    public var suggestion: String?

    public init(
        index: Int? = nil, condition: Condition? = nil, value: String? = nil, browser: String? = nil,
        browserName: String? = nil, browserID: String? = nil, profile: String? = nil,
        profileName: String? = nil,
        id: String? = nil, time: String? = nil, url: String? = nil, agent: String? = nil,
        suggestion: String? = nil
    ) {
        self.index = index
        self.condition = condition
        self.value = value
        self.browser = browser
        self.browserName = browserName
        self.browserID = browserID
        self.profile = profile
        self.profileName = profileName
        self.id = id
        self.time = time
        self.url = url
        self.agent = agent
        self.suggestion = suggestion
    }

    enum CodingKeys: String, CodingKey {
        case index, condition, value, browser, browserName, profile, profileName, id, time, url, agent,
            suggestion
        case browserID = "browserId"
    }
}

public struct OperationError: Error, Equatable, Codable, CustomStringConvertible, Sendable {
    public var code: Code
    public var message: String
    public var candidates: [Candidate]

    public init(_ code: Code, _ message: String, candidates: [Candidate] = []) {
        self.code = code
        self.message = message
        self.candidates = candidates
    }

    public static func invalid(_ message: String) -> OperationError {
        OperationError(.invalidArgument, message)
    }

    public func with(_ candidates: [Candidate]) -> OperationError {
        var copy = self
        copy.candidates = candidates
        return copy
    }

    public init(_ error: StoreError) {
        switch error {
        case .unreadable: self.init(.configUnreadable, error.description)
        case .invalid: self.init(.configInvalid, error.description)
        case .conflict:
            self.init(
                .conflict,
                "The configuration changed while this command ran. Nothing was written. Run it again.")
        case .writeFailed: self.init(.writeFailed, error.description)
        }
    }

    public var description: String { message }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(code, forKey: AnyKey("code"))
        try c.encode(message, forKey: AnyKey("message"))
        if !candidates.isEmpty { try c.encode(candidates, forKey: AnyKey("candidates")) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        code = try c.decode(Code.self, forKey: AnyKey("code"))
        message = try c.decode(String.self, forKey: AnyKey("message"))
        candidates = try c.decodeIfPresent([Candidate].self, forKey: AnyKey("candidates")) ?? []
    }
}
