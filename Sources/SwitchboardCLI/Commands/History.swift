import SwitchboardCore

extension HistoryList: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let snapshot = try session.load()
        let entries = try session.historyEntries(snapshot.config).prefix(limit).map {
            EntryReport($0, fullURL: fullUrls, session)
        }
        let now = session.context.now
        let ages = entries.map { e in Timestamp(rfc3339: e.time).map { $0.ago(now) } ?? e.time }
        let ageWidth = (ages.map(\.count).max() ?? 0) + 2
        let urlWidth = min(entries.map(\.url.count).max() ?? 0, 60) + 2
        var text = entries.isEmpty ? "No links in history yet.\n" : ""
        for (entry, age) in zip(entries, ages) {
            let failed = entry.result == .failed ? "  (failed: \(entry.error ?? "unknown error"))" : ""
            text +=
                "\(entry.id)  \(Format.padded(age, ageWidth))\(Format.padded(entry.url, urlWidth))\(entry.how) → \(entry.destination)\(failed)\n"
        }
        var report = JSONObject()
        report.set("path", session.historyURL.path)
        report.set("enabled", true)
        report.set("entries", entries)
        return Output(json: report, text: text)
    }
}

extension HistoryClear: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let store = session.history
        let count: Int
        do {
            count = dryRun ? try store.entries().count : try store.clear()
        } catch {
            throw writeFailed("The history couldn’t be cleared.", error.message)
        }
        let noun = count == 1 ? "entry" : "entries"
        var report = JSONObject()
        report.set("path", session.historyURL.path)
        report.set("entries", count)
        report.set("dryRun", dryRun)
        return Output(json: report, text: "\(dryRun ? "Would clear" : "Cleared") \(count) history \(noun).\n")
    }
}

extension HistoryOn: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        try setHistory(session, change, on: true)
    }
}

extension HistoryOff: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        try setHistory(session, change, on: false)
    }
}

private func setHistory(_ session: Session, _ change: ChangeOptions, on: Bool) throws(OperationError)
    -> Output
{
    try changeSetting(
        session, change,
        // Omitted means on, which keeps the file minimal.
        edit: { _, config in config.history = on ? nil : HistorySettings(enabled: false) },
        value: { config in
            var o = JSONObject()
            o.set("enabled", config.historyEnabled)
            return o
        },
        describe: { "history \($0.historyEnabled ? "on" : "off")." })
}
