import Foundation
import SwitchboardCore

// A rule started from a link in Recent Links.

extension Draft {
    /// A new rule for a link that opened: its domain, or the whole link when it has no host.
    ///
    /// A link chosen in Quick Switch keeps the destination the person picked, since a rule makes
    /// that choice automatic. Any other link already went where the rules or the default sent it,
    /// so it starts on `firstProfile`, the default browser's first, like any new rule.
    public static func forLink(_ entry: History.Entry, defaultBrowser: String, firstProfile: String) -> Draft
    {
        var draft = newRule(profile: firstProfile)
        if let host = Link.webHost(entry.url) {
            draft.condition = .domain
            draft.value = domain(of: host)
        } else {
            draft.condition = .exact
            draft.value = entry.url
        }
        if entry.source == .picker {
            draft.browser = entry.browser == defaultBrowser ? nil : entry.browser
            draft.profile = entry.profile
        }
        return draft
    }

    /// `www.github.com` → `github.com`, so the rule also matches the bare domain and its other
    /// subdomains. A host that is only `www.` and one label stays as it is.
    static func domain(of host: String) -> String {
        let rest = host.dropFirst(4)
        guard host.hasPrefix("www."), rest.contains(".") else { return host }
        return String(rest)
    }
}

extension History.Entry {
    /// Why the link went where it did, as Recent Links shows it.
    public var reason: String {
        switch source {
        case .rule:
            guard let rule else { return "Sent by a rule" }
            return "Rule \(rule.index): \(rule.condition.label) \(rule.value)"
        case .default: return "No rule matched, so the default"
        case .picker: return "Chosen in Quick Switch"
        }
    }
}
