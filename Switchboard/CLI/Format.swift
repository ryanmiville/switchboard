import Foundation

// Human-readable output. JSON output comes from the report types instead.
enum Format {
    static func short(_ revision: String) -> String { String(revision.prefix(12)) }

    static func destination(_ destination: DestinationInfo) -> String { RuleOperations.label(destination) }

    static func rule(_ reference: RuleReference) -> String { RuleOperations.describe(reference) }

    static func via(_ decision: DecisionInfo) -> String {
        decision.rule.map { "[rule \($0.index)]" } ?? "[default]"
    }

    static func decision(_ decision: DecisionInfo) -> String {
        "\(destination(decision.destination))  \(via(decision))"
    }

    static func ruleLine(_ rule: RuleInfo) -> String {
        "\(rule.condition.rawValue) \(rule.value) → \(destination(rule.destination))"
    }

    // A warning line for a destination whose profile no longer resolves, or nil when it does.
    static func problem(_ status: ProfileStatus, _ destination: DestinationInfo) -> String? {
        switch status {
        case .ok: nil
        case .missing:
            "The profile “\(destination.profile)” doesn’t exist in \(destination.browserName). Run `switchboard profiles` to choose another."
        case .ambiguous:
            "Several profiles in \(destination.browserName) are named “\(destination.profile)”. Choose one by its directory."
        case .unavailable:
            "\(destination.browserName) isn’t installed at \(destination.browser), or its profiles couldn’t be read."
        }
    }

    static func candidate(_ candidate: Candidate) -> String {
        var line: String
        if let index = candidate.index {
            line = "rule \(index)"
            if let condition = candidate.condition, let value = candidate.value {
                line += ": \(condition.rawValue) \(value)"
            }
        } else if let id = candidate.id {
            line = [id, candidate.url].compactMap { $0 }.joined(separator: "  ")
        } else if let profile = candidate.profile {
            line =
                "\(candidate.browserName ?? candidate.browser ?? "") · \(candidate.profileName ?? profile) (\(profile))"
        } else if let browser = candidate.browser {
            line = "\(candidate.browserName ?? browser)  \(browser)"
            if let bundleIdentifier = candidate.bundleIdentifier { line += "  (\(bundleIdentifier))" }
        } else {
            line = candidate.agent ?? ""
        }
        var text = "  - \(line)\n"
        if let suggestion = candidate.suggestion { text += "    \(suggestion)\n" }
        return text
    }

    static func age(_ time: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(time)))
        switch seconds {
        case ..<60: return "\(seconds)s ago"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86400)d ago"
        }
    }

    static func padded(_ value: String, to width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }

    static func written(dryRun: Bool, revision: String) -> String {
        dryRun ? "No changes written (dry run).\n" : "Saved. Revision \(short(revision)).\n"
    }

    static func historyChanges(_ changes: [HistoryChangeReport], checked: Bool) -> String {
        guard checked else { return "" }
        guard !changes.isEmpty else { return "No recent links would open somewhere else.\n" }
        var text = "Recent links that would now open somewhere else:\n"
        for change in changes {
            text +=
                "  \(change.id)  \(change.url)\n    \(decision(change.before))  →  \(decision(change.after))\n"
        }
        return text
    }

    static func unreachable(_ rules: [RuleReference]) -> String {
        rules.map { "  ! Rule \($0.index) (\(rule($0))) can no longer match.\n" }.joined()
    }
}
