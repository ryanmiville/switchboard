import Foundation

// A failure the CLI reports with a stable code and exit status. Not-found and ambiguous failures list the
// candidates to choose from and never change anything.
struct OperationError: LocalizedError {
    enum Code: String, Encodable {
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

        var exitCode: Int32 {
            switch self {
            case .invalidArgument: 64
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

    var code: Code
    var message: String
    var candidates: [Candidate] = []

    var errorDescription: String? { message }

    static func invalidArgument(_ message: String) -> OperationError {
        OperationError(code: .invalidArgument, message: message)
    }

    init(code: Code, message: String, candidates: [Candidate] = []) {
        self.code = code
        self.message = message
        self.candidates = candidates
    }

    init(_ error: ConfigStoreError) {
        switch error {
        case .unreadable: self.init(code: .configUnreadable, message: error.localizedDescription)
        case .invalid: self.init(code: .configInvalid, message: error.localizedDescription)
        case .conflict:
            self.init(
                code: .conflict,
                message:
                    "The configuration changed while this command ran. Nothing was written. Run it again.")
        }
    }
}

// One choice in a not-found or ambiguous answer. Only the fields that apply are present.
struct Candidate: Encodable, Equatable {
    var index: Int? = nil
    var condition: Condition? = nil
    var value: String? = nil
    var browser: String? = nil
    var browserName: String? = nil
    var bundleIdentifier: String? = nil
    var profile: String? = nil
    var profileName: String? = nil
    var id: String? = nil
    var time: Date? = nil
    var url: String? = nil
    var agent: String? = nil
    // A command that resolves the problem for this candidate.
    var suggestion: String? = nil
}
