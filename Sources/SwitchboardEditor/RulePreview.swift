import Foundation
import SwitchboardCore

// What the rule sheet shows under the pattern as it is typed: which links the pattern matches,
// whether it can match at all, whether an earlier rule takes those links first, and which of the
// person's recent links it would have matched.

public struct RulePreview: Equatable, Sendable {
    /// What the pattern matches, in a sentence; `nil` when it isn't a pattern of its kind.
    public var summary: String?
    /// Why the pattern can't be saved or can never match, when it can't.
    public var problem: String?
    /// The earlier rule that matches every link this one would, so this one never matches.
    public var hiddenBy: String?
    /// How many of `total` recent links the pattern matches, with a few of them redacted.
    public var recent: Recent?

    public struct Recent: Equatable, Sendable {
        public var matched: Int
        public var total: Int
        public var examples: [String]

        public var text: String {
            matched == 0
                ? "None of your last \(total) links match."
                : "Matches \(matched) of your last \(total) links\(examples.isEmpty ? "." : ", such as:")"
        }
    }

    /// Recent links shown as examples, at most.
    public static let exampleCount = 3
}

extension Draft {
    /// The preview for this draft among `rules` (the config's, this draft's own included when
    /// editing), and the `recent` links from history, newest first. `nil` while the pattern is empty.
    public func preview(rules: [Rule], recent: [String]) -> RulePreview? {
        let pattern = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }
        var preview = RulePreview(summary: Self.summary(condition, pattern))
        if condition == .domain {
            do {
                try RuleOperations.validateDomain(pattern)
            } catch {
                return RulePreview(summary: nil, problem: error.message)
            }
        }
        if condition == .exact, !(Link.isWeb(pattern) || Link.isLocalFile(pattern)) {
            preview.problem =
                "Links always arrive whole, so an Exact pattern needs a complete link, such as https://example.com/login."
        }
        var rule = Rule(condition, pattern, profile: profile, browser: browser)
        rule.id = id
        let earlier = rules.firstIndex { $0.id == id }.map { Array(rules[..<$0]) } ?? rules
        if let by = earlier.firstIndex(where: { Shadowing.covers($0, rule) }) {
            let hider = earlier[by]
            preview.hiddenBy =
                "Never matches: rule \(by + 1) (\(hider.condition.label) \(hider.value)) matches all of these links first."
        }
        if !recent.isEmpty {
            let matching = recent.filter { Router.matches(rule, link: $0) }
            preview.recent = RulePreview.Recent(
                matched: matching.count, total: recent.count,
                examples: matching.prefix(RulePreview.exampleCount).map(History.redact))
        }
        return preview
    }

    static func summary(_ condition: Condition, _ pattern: String) -> String {
        switch condition {
        case .domain:
            "Links to \(pattern) and anything ending in .\(pattern). Not my\(pattern)."
        case .contains:
            "Every link with “\(pattern)” anywhere in it, in any case."
        case .exact:
            "Only this exact link, in any case. Another path, query or fragment doesn’t match."
        }
    }
}
