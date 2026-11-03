// Rule matching. The first matching rule wins; otherwise the default destination.
//
// Comparisons run on lowercased UTF-8 bytes, as the Rust rewrite does. Swift's String comparison
// treats canonically equivalent text as equal, which would let a pattern match a link whose bytes
// differ.

/// Where a link goes, and the index of the rule that sent it there (`nil` for the default).
public struct Decision: Equatable, Sendable {
    public var destination: Destination
    public var rule: Int?
}

public enum Router {
    public static func decide(_ config: Config, link: String) -> Decision {
        let lowered = Array(link.lowercased().utf8)
        let host = Link.webHost(link).map { Array($0.utf8) }
        for (index, rule) in config.rules.enumerated() where matches(rule, lowered: lowered, host: host) {
            return Decision(destination: config.destination(of: rule), rule: index)
        }
        return Decision(destination: config.defaultDestination, rule: nil)
    }

    /// Whether `rule` matches `link`, ignoring every other rule.
    public static func matches(_ rule: Rule, link: String) -> Bool {
        matches(rule, lowered: Array(link.lowercased().utf8), host: Link.webHost(link).map { Array($0.utf8) })
    }

    static func matches(_ rule: Rule, lowered: [UInt8], host: [UInt8]?) -> Bool {
        let value = Array(rule.value.lowercased().utf8)
        if value.isEmpty { return false }
        switch rule.condition {
        case .contains: return Bytes.contains(lowered, value)
        case .exact: return lowered == value
        case .domain: return host.map { Bytes.isDomain($0, within: value) } ?? false
        }
    }
}

enum Bytes {
    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        if needle.isEmpty { return true }
        if needle.count > haystack.count { return false }
        for start in 0...(haystack.count - needle.count) where haystack[start] == needle[0] {
            if haystack[start..<(start + needle.count)].elementsEqual(needle) { return true }
        }
        return false
    }

    /// `host` is `domain` or a subdomain of it at a dot boundary.
    static func isDomain(_ host: [UInt8], within domain: [UInt8]) -> Bool {
        if host == domain { return true }
        guard host.count > domain.count, host.suffix(domain.count).elementsEqual(domain) else { return false }
        return host[host.count - domain.count - 1] == UInt8(ascii: ".")
    }
}
