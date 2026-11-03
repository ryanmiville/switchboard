import SwitchboardCore

extension RouteCommand: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let snapshot = try session.load()
        try session.check(snapshot, change)
        let linked = try session.link(link, snapshot.config)
        let operations = session.operations(snapshot)
        let result = try operations.route(
            RouteRequest(
                url: linked.url, profile: profile, browser: browser, condition: condition.condition,
                value: value,
                allowShadowing: allowShadowing))
        let revision = try session.commit(result.config, snapshot, dryRun: change.dryRun)
        let edited = operations.with(result.config)
        let before = operations.decision(linked.url)
        let after = edited.decision(linked.url)
        let rule = result.index.map { edited.rules()[$0] }
        let shadowed = result.unreachable.map { edited.reference($0.rule) }
        let dry = change.dryRun
        let text: String
        if let rule, result.changed {
            let verb =
                switch (result.action, dry) {
                case (.added, true): "Would add"
                case (.added, false): "Added"
                case (_, true): "Would update"
                case (_, false): "Updated"
                }
            text =
                "\(verb) rule \(rule.index): \(Format.ruleLine(rule))\n  before: \(Format.decision(before))\n  after:  \(Format.decision(after))\n"
                + Format.unreachable(shadowed) + Format.written(dryRun: dry, revision)
        } else {
            text = "Nothing to change: the URL already opens in \(Format.decision(before)).\n"
        }
        var report = JSONObject()
        report.set("url", linked.display)
        report.set("action", result.action)
        report.set("changed", result.changed)
        report.set("written", result.changed && !dry)
        report.set("dryRun", dry)
        report.set("rule", rule)
        report.set("before", before)
        report.set("after", after)
        report.set("shadowedRules", shadowed)
        report.set("revision", revision)
        return Output(json: report, text: text)
    }
}
