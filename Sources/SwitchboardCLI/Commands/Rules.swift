import SwitchboardCore

extension RulesList: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let snapshot = try session.load()
        let operations = session.operations(snapshot)
        let rules = operations.rules()
        let defaults = DefaultInfo(operations)
        var text = "Default: \(defaults.destination.label)\n"
        if let problem = Format.problem(defaults.profileStatus, defaults.destination) {
            text += "  ! \(problem)\n"
        }
        if rules.isEmpty { text += "No rules. Every link uses the default destination.\n" }
        let width = min(rules.map { max($0.value.count, 1) }.max() ?? 0, 40)
        for rule in rules {
            let pattern = rule.value.isEmpty ? "(empty, ignored)" : rule.value
            text +=
                Format.padded(String(rule.index), 3) + Format.padded(rule.condition.rawValue, 10)
                + Format.padded(pattern, width) + "  → \(rule.destination.label)"
                + (rule.browser == nil ? "  (default browser)" : "") + "\n"
            if let problem = Format.problem(rule.profileStatus, rule.destination) {
                text += "     ! \(problem)\n"
            }
            if let by = rule.shadowedBy { text += "     ! Never matches: rule \(by) always matches first.\n" }
        }
        text += "Revision \(Format.short(snapshot.revision))\n"
        var report = JSONObject()
        report.set("rules", rules)
        report.set("default", defaults)
        report.set("revision", snapshot.revision)
        return Output(json: report, text: text)
    }
}

extension RulesUpdate: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let (snapshot, operations) = try start(session, change)
        let choice: BrowserChoice? = defaultBrowser ? .default : browser.map { .browser($0) }
        let result = try operations.updateRule(
            position,
            RuleUpdate(
                profile: profile, browser: choice, condition: condition?.condition, value: value,
                allowShadowing: allowShadowing))
        let previous = operations.rules()[position - 1]
        let rule = operations.with(result.config).rules()[position - 1]
        let line = Format.ruleLine(rule)
        let index = rule.index
        return try finish(
            session, snapshot, operations, result, change, rule: rule, previous: previous, moved: nil
        ) {
            changed, dry in
            changed
                ? "\(dry ? "Would update" : "Updated") rule \(index): \(line)\n"
                : "Nothing to change: rule \(index) is already \(line).\n"
        }
    }
}

extension RulesMove: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let (snapshot, operations) = try start(session, change)
        let result = try operations.moveRule(from: from, to: to)
        let rule = operations.with(result.config).rules()[to - 1]
        let line = Format.ruleLine(rule)
        let (from, to) = (from, to)
        return try finish(
            session, snapshot, operations, result, change, rule: rule, previous: nil, moved: (from, to)
        ) {
            changed, dry in
            changed
                ? "\(dry ? "Would move" : "Moved") rule \(from) to position \(to): \(line)\n"
                : "Nothing to change: rule \(from) is already at position \(to).\n"
        }
    }
}

extension RulesRemove: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let (snapshot, operations) = try start(session, change)
        let result = try operations.removeRule(position)
        let rule = operations.rules()[position - 1]
        let line = "rule \(rule.index): \(Format.ruleLine(rule))"
        return try finish(
            session, snapshot, operations, result, change, rule: rule, previous: nil, moved: nil
        ) {
            _, dry in "\(dry ? "Would remove" : "Removed") \(line)\n"
        }
    }
}

private func start(_ session: Session, _ change: ChangeOptions) throws(OperationError)
    -> (ConfigStore.Snapshot, RuleOperations)
{
    let snapshot = try session.load()
    try session.check(snapshot, change)
    return (snapshot, session.operations(snapshot))
}

/// One shared tail for the three position-based commands.
private func finish(
    _ session: Session, _ snapshot: ConfigStore.Snapshot, _ operations: RuleOperations, _ result: RuleChange,
    _ change: ChangeOptions, rule: RuleInfo, previous: RuleInfo?, moved: (Int, Int)?,
    headline: (_ changed: Bool, _ dryRun: Bool) -> String
) throws(OperationError) -> Output {
    let revision = try session.commit(result.config, snapshot, dryRun: change.dryRun)
    let edited = operations.with(result.config)
    let shadowed = result.unreachable.map { edited.reference($0.rule) }
    let (checked, changes) = historyChanges(session, operations, result.config)
    let changed = result.changed
    var text = headline(changed, change.dryRun)
    if changed {
        if let previous { text += "  was: \(Format.ruleLine(previous))\n" }
        text += Format.unreachable(shadowed)
        text += Format.historyChanges(changes, checked: checked)
        text += Format.written(dryRun: change.dryRun, revision)
    }
    var report = JSONObject()
    report.set("action", result.action)
    report.set("changed", changed)
    report.set("written", changed && !change.dryRun)
    report.set("dryRun", change.dryRun)
    report.set("rule", rule)
    report.setIfPresent("previous", previous)
    report.setIfPresent("from", moved?.0)
    report.setIfPresent("to", moved?.1)
    report.set("shadowedRules", shadowed)
    report.set("historyChecked", checked)
    report.set("historyChanges", changes)
    report.set("revision", revision)
    return Output(json: report, text: text)
}

extension DefaultCommand: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let snapshot = try session.load()
        let operations = session.operations(snapshot)
        let current = DefaultInfo(operations)
        if browser == nil && profile == nil {
            var text = "Default: \(current.destination.label)\n"
            if let problem = Format.problem(current.profileStatus, current.destination) {
                text += "  ! \(problem)\n"
            }
            var report = JSONObject()
            report.set("destination", current.destination)
            report.set("profileStatus", current.profileStatus)
            report.set("revision", snapshot.revision)
            return Output(json: report, text: text)
        }
        try session.check(snapshot, change)
        let result = try operations.setDefault(browser: browser, profile: profile)
        let revision = try session.commit(result.config, snapshot, dryRun: change.dryRun)
        let updated = DefaultInfo(operations.with(result.config))
        let (checked, changes) = historyChanges(session, operations, result.config)
        let dry = change.dryRun
        let text =
            result.changed
            ? "\(dry ? "Would change" : "Changed") the default to \(updated.destination.label)\n  was: \(current.destination.label)\n"
                + Format.historyChanges(changes, checked: checked) + Format.written(dryRun: dry, revision)
            : "Nothing to change: the default is already \(current.destination.label).\n"
        var report = JSONObject()
        report.set("changed", result.changed)
        report.set("written", result.changed && !dry)
        report.set("dryRun", dry)
        report.set("before", current)
        report.set("destination", updated.destination)
        report.set("profileStatus", updated.profileStatus)
        report.set("historyChecked", checked)
        report.set("historyChanges", changes)
        report.set("revision", revision)
        return Output(json: report, text: text)
    }
}
