import SwitchboardCore

// Report pieces and the settings-change flow shared by several commands.

struct DefaultInfo: Encodable {
    var destination: DestinationInfo
    var profileStatus: ProfileStatus

    init(_ operations: RuleOperations) {
        (destination, profileStatus) = operations.describe(operations.config.defaultDestination)
    }
}

struct HistoryChangeReport: Encodable {
    var id: String
    var url: String
    var before: DecisionInfo
    var after: DecisionInfo
}

/// Recent links whose destination `edited` would change, and whether history could be checked.
func historyChanges(_ session: Session, _ operations: RuleOperations, _ edited: Config)
    -> (checked: Bool, changes: [HistoryChangeReport])
{
    guard let entries = session.recentHistory(operations.config) else { return (false, []) }
    let changes = operations.historyChanges(edited, entries: entries).map {
        HistoryChangeReport(id: $0.entry.id, url: $0.entry.redactedURL, before: $0.before, after: $0.after)
    }
    return (true, changes)
}

/// Applies `edit` to the loaded config and commits it: the shape of `history on|off` and `picker`.
func changeSetting(
    _ session: Session, _ change: ChangeOptions,
    edit: (RuleOperations, inout Config) throws(OperationError) -> Void,
    value: (Config) -> any Encodable,
    describe: (Config) -> String
) throws(OperationError) -> Output {
    let snapshot = try session.load()
    try session.check(snapshot, change)
    let operations = session.operations(snapshot)
    var edited = snapshot.config
    try edit(operations, &edited)
    let changed = edited != snapshot.config
    let revision = try session.commit(edited, snapshot, dryRun: change.dryRun)
    let text =
        changed
        ? "\(change.dryRun ? "Would set" : "Set") \(describe(edited))\n\(Format.written(dryRun: change.dryRun, revision))"
        : "Nothing to change: \(describe(edited))\n"
    var report = JSONObject()
    report.set("changed", changed)
    report.set("written", changed && !change.dryRun)
    report.set("dryRun", change.dryRun)
    report.set("value", value(edited))
    report.set("revision", revision)
    return Output(json: report, text: text)
}

func writeFailed(_ what: String, _ error: String) -> OperationError {
    OperationError(.writeFailed, "\(what) \(error)")
}
