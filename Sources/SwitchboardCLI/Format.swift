import SwitchboardCore

// Human-readable output. JSON output comes from the reports instead.

enum Format {
    static func short(_ revision: String) -> String { String(revision.prefix(12)) }

    static func via(_ decision: DecisionInfo) -> String {
        decision.rule.map { "[rule \($0.index)]" } ?? "[default]"
    }

    static func decision(_ decision: DecisionInfo) -> String {
        "\(decision.destination.label)  \(via(decision))"
    }

    static func ruleLine(_ rule: RuleInfo) -> String {
        "\(rule.condition.rawValue) \(rule.value) → \(rule.destination.label)"
    }

    /// A warning for a destination whose profile no longer resolves.
    static func problem(_ status: ProfileStatus, _ d: DestinationInfo) -> String? {
        switch status {
        case .ok: nil
        case .missing:
            "The profile “\(d.profile)” doesn’t exist in \(d.browserName). Run `\(Identity.cliName) profiles` to choose another."
        case .ambiguous:
            "Several profiles in \(d.browserName) are named “\(d.profile)”. Choose one by its directory."
        case .unavailable where d.browser.isEmpty:
            "No default browser is chosen. Run `\(Identity.cliName) default --browser <browser> --profile <profile>`."
        case .unavailable:
            "\(d.browserName) isn’t installed at \(d.browser), or its profiles couldn’t be read."
        }
    }

    static func candidate(_ c: Candidate) -> String {
        let line: String
        if let index = c.index {
            if let condition = c.condition, let value = c.value {
                line = "rule \(index): \(condition.rawValue) \(value)"
            } else {
                line = "rule \(index)"
            }
        } else if let id = c.id {
            line = [id, c.url].compactMap { $0 }.joined(separator: "  ")
        } else if let profile = c.profile {
            line = "\(c.browserName ?? c.browser ?? "") · \(c.profileName ?? profile) (\(profile))"
        } else if let browser = c.browser {
            line = "\(c.browserName ?? browser)  \(browser)\(c.browserID.map { "  (\($0))" } ?? "")"
        } else {
            line = c.agent ?? ""
        }
        var text = "  - \(line)\n"
        if let suggestion = c.suggestion { text += "    \(suggestion)\n" }
        return text
    }

    static func padded(_ value: String, _ width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }

    static func written(dryRun: Bool, _ revision: String) -> String {
        dryRun ? "No changes written (dry run).\n" : "Saved. Revision \(short(revision)).\n"
    }

    static func historyChanges(_ changes: [HistoryChangeReport], checked: Bool) -> String {
        guard checked else { return "" }
        if changes.isEmpty { return "No recent links would open somewhere else.\n" }
        var text = "Recent links that would now open somewhere else:\n"
        for c in changes {
            text += "  \(c.id)  \(c.url)\n    \(decision(c.before))  →  \(decision(c.after))\n"
        }
        return text
    }

    static func unreachable(_ rules: [RuleRef]) -> String {
        rules.map { "  ! Rule \($0.index) (\($0.describe)) can no longer match.\n" }.joined()
    }
}
