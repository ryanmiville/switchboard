import SwitchboardCore

// `picker`: the Quick Switch picker's shortcut and which destinations it shows.

private func settings(_ config: Config) -> PickerSettings { config.picker ?? PickerSettings() }

private func describe(_ config: Config) -> String {
    let s = settings(config)
    let shown =
        s.destinations.map { "\($0.count) destination\($0.count == 1 ? "" : "s")" } ?? "every destination"
    return "the picker: shortcut \(s.shortcut.text), showing \(shown)."
}

/// Resolves a browser and profile the way `route` does, into what the config saves.
private func destination(_ operations: RuleOperations, _ browser: String, _ profile: String)
    throws(OperationError)
    -> (Destination, String)
{
    let info = try operations.resolveBrowser(browser)
    let found = try operations.resolveProfile(profile, in: info.locator)
    return (Destination(browser: info.locator, profile: found.directory), found.name)
}

private func changePicker(
    _ session: Session, _ change: ChangeOptions,
    _ edit: (RuleOperations, inout PickerSettings) throws(OperationError) -> Void
) throws(OperationError) -> Output {
    try changeSetting(
        session, change,
        edit: { operations, config throws(OperationError) in
            var s = settings(config)
            try edit(operations, &s)
            config.picker = s
        },
        value: settings, describe: describe)
}

extension PickerShow: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let snapshot = try session.load()
        let s = settings(snapshot.config)
        let browsers = session.context.browsers
        var text = "Shortcut: \(s.shortcut.text)\n"
        if let list = s.destinations {
            text += "Shows \(list.count) destinations:\n"
            for d in list { text += "  \(browsers.displayName(d.browser)) · \(d.profile)\n" }
        } else {
            text += "Shows every installed destination.\n"
        }
        var report = JSONObject()
        report.set("picker", s)
        report.set("revision", snapshot.revision)
        return Output(json: report, text: text)
    }
}

extension PickerShortcut: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let text = shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try changePicker(session, change) { _, s throws(OperationError) in
            if !text.contains("+") || text.hasSuffix("+") {
                throw .invalid("Write a shortcut as modifiers and a key, such as ctrl+alt+space.")
            }
            s.shortcut = Shortcut(text)
        }
    }
}

extension PickerDestination: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        try changePicker(session, change) { operations, s throws(OperationError) in
            let (d, _) = try destination(operations, browser, profile)
            if only {
                s.destinations = [d]
                return
            }
            // Hiding one destination from "show everything" starts an explicit list of the rest.
            var shown =
                s.destinations
                ?? operations.knownBrowsers().flatMap { info in
                    ((try? operations.profiles(info.locator)) ?? []).map {
                        Destination(browser: info.locator, profile: $0.directory)
                    }
                }
            shown.removeAll { $0 == d }
            if !hide { shown.append(d) }
            s.destinations = shown
        }
    }
}

extension PickerShowAll: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        try changePicker(session, change) { _, s in s.destinations = nil }
    }
}
