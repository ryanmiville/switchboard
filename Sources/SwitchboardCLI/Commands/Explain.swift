import SwitchboardCore

/// A history entry as the CLI reports it.
struct EntryReport: Encodable {
    var id: String
    var time: String
    var url: String
    var source: History.Source
    var rule: History.RuleSnapshot?
    var browser: String
    var browserName: String
    var profile: String
    var profileName: String?
    var result: History.Outcome
    var error: String?

    init(_ entry: History.Entry, fullURL: Bool, _ session: Session) {
        id = entry.id
        time = entry.time
        url = fullURL ? entry.url : entry.redactedURL
        source = entry.source
        rule = entry.rule
        browser = entry.browser
        browserName = session.context.browsers.displayName(entry.browser)
        profile = entry.profile
        profileName = entry.profileName
        result = entry.result
        error = entry.error
    }

    func encode(to encoder: Encoder) throws {
        var o = JSONObject()
        o.set("id", id)
        o.set("time", time)
        o.set("url", url)
        o.set("source", source)
        o.setIfPresent("rule", rule)
        o.set("browser", browser)
        o.set("browserName", browserName)
        o.set("profile", profile)
        o.set("profileName", profileName)
        o.set("result", result)
        o.setIfPresent("error", error)
        try o.encode(to: encoder)
    }

    /// "rule 2" or "default" or "picker".
    var how: String { rule.map { "rule \($0.index)" } ?? source.rawValue }

    var destination: String { "\(browserName) · \(profileName ?? profile)" }

    var summary: String {
        let how = rule.map { "rule \($0.index) (\($0.condition.rawValue) \($0.value))" } ?? self.how
        let outcome =
            switch result {
            case .failed: ", failed: \(error ?? "unknown error")"
            case .launched: ", launched"
            }
        return "\(how) → \(destination)\(outcome)"
    }
}

extension ExplainCommand: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let snapshot = try session.load()
        let linked = try session.link(link, snapshot.config)
        let explanation = session.operations(snapshot).explain(linked.url)
        let decision = explanation.decision
        let history = linked.entry.map { EntryReport($0, fullURL: link.fullUrls, session) }
        var text = linked.entry != nil ? "URL: \(linked.display)\n" : ""
        if let rule = decision.rule {
            text += "Rule \(rule.index) matched: \(rule.describe)\n"
        } else {
            text += "No rule matched; using the default destination.\n"
        }
        text += "  → \(decision.destination.label)\n"
        if let problem = Format.problem(decision.profileStatus, decision.destination) {
            text += "  ! \(problem)\n"
        }
        if !explanation.alsoMatches.isEmpty {
            let list = explanation.alsoMatches.map { "rule \($0.index) (\($0.describe))" }
            text += "Also matches, but never reached: \(list.joined(separator: ", "))\n"
        }
        if let history, let entry = linked.entry {
            let age = entry.timestamp.map { $0.ago(session.context.now) } ?? history.time
            text += "At the time (\(age)): \(history.summary)\n"
        }
        var report = JSONObject()
        report.set("url", linked.display)
        report.set("matchedRule", decision.rule)
        report.set("destination", decision.destination)
        report.set("profileStatus", decision.profileStatus)
        report.set("alsoMatches", explanation.alsoMatches)
        report.set("revision", snapshot.revision)
        report.setIfPresent("history", history)
        return Output(json: report, text: text)
    }
}
