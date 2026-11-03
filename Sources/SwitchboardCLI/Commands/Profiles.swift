import SwitchboardCore

extension ProfilesCommand: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        let snapshot = try session.load()
        let operations = session.operations(snapshot)
        let browsers =
            try browser.map { query throws(OperationError) in [try operations.resolveBrowser(query)] }
            ?? operations.knownBrowsers()
        let defaultBrowser = session.context.browsers.standardize(snapshot.config.browser)
        var reports: [JSONObject] = []
        var text = browsers.isEmpty ? "No supported Chromium browsers found.\n" : ""
        for info in browsers {
            var profiles: [Profile] = []
            var error: String?
            do {
                profiles = try Profiles.read(info)
            } catch let failure {
                error = failure.description
            }
            let isDefault = info.locator == defaultBrowser
            var report = JSONObject()
            report.set("name", info.name)
            report.set("path", info.locator)
            report.set("id", info.id)
            report.set("isDefault", isDefault)
            report.set("localState", info.userData.appendingPathComponent("Local State").path)
            report.set(
                "profiles",
                profiles.map { p -> JSONObject in
                    var o = JSONObject()
                    o.set("profile", p.directory)
                    o.set("profileName", p.name)
                    return o
                })
            report.setIfPresent("error", error)
            reports.append(report)

            text += "\(info.name)\(isDefault ? " (default browser)" : "")  \(info.locator)  (\(info.id))\n"
            if let error { text += "  ! \(error)\n" }
            let width = (profiles.map(\.directory.count).max() ?? 0) + 2
            for p in profiles { text += "  \(Format.padded(p.directory, width))\(p.name)\n" }
        }
        var report = JSONObject()
        report.set("browsers", reports)
        return Output(json: report, text: text)
    }
}

extension ConfigCommand: Runnable {
    /// The whole configuration as the app reads it, with its path and revision.
    func execute(_ session: Session) throws(OperationError) -> Output {
        let snapshot = try session.load()
        let path = session.configURL.path
        var report = JSONObject()
        report.set("path", path)
        report.set("exists", snapshot.exists)
        report.set("revision", snapshot.revision)
        report.set("config", snapshot.config)
        let text =
            "\(path)\(snapshot.exists ? "" : " (not created yet; these are the defaults)")\n"
            + String(decoding: snapshot.config.encoded(), as: UTF8.self)
        return Output(json: report, text: text)
    }
}
