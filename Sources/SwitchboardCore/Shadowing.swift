// Rules that can never match because an earlier rule matches every link they would.

public struct Unreachable: Equatable, Sendable {
    /// 0-based index of the rule that never matches.
    public var rule: Int
    /// 0-based index of the earlier rule that always matches first.
    public var by: Int
}

public enum Shadowing {
    /// Whether `earlier` matches every link `later` would.
    public static func covers(_ earlier: Rule, _ later: Rule) -> Bool {
        let first = Array(earlier.value.lowercased().utf8)
        let second = Array(later.value.lowercased().utf8)
        if first.isEmpty || second.isEmpty { return false }
        switch (earlier.condition, later.condition) {
        // An exact rule matches one link; it is hidden if the earlier rule matches that link.
        case (_, .exact): return Router.matches(earlier, link: later.value)
        // Every link a domain rule matches contains its domain.
        case (.contains, .contains), (.contains, .domain): return Bytes.contains(second, first)
        case (.domain, .domain): return Bytes.isDomain(second, within: first)
        case (.domain, .contains), (.exact, .contains), (.exact, .domain): return false
        }
    }

    public static func unreachable(_ rules: [Rule]) -> [Unreachable] {
        rules.indices.compactMap { later in
            rules[..<later].firstIndex { covers($0, rules[later]) }.map { Unreachable(rule: later, by: $0) }
        }
    }

    /// Rules unreachable in `after` that weren't already unreachable in `before`, followed by id.
    public static func newlyUnreachable(before: [Rule], after: [Rule]) -> [Unreachable] {
        let existing = Set(unreachable(before).map { before[$0.rule].id })
        return unreachable(after).filter { !existing.contains(after[$0.rule].id) }
    }
}
