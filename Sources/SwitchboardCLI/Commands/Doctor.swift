import Foundation
import SwitchboardCore

// `doctor`: checks the configuration, browsers, profiles and history. Changes nothing.

extension DoctorCommand: Runnable {
    func execute(_ session: Session) throws(OperationError) -> Output {
        var r = DoctorReport(
            configPath: session.configURL.path,
            configExists: FileManager.default.fileExists(atPath: session.configURL.path),
            historyPath: session.historyURL.path)
        let store = session.store
        do {
            let snapshot = try store.load()
            r.configValid = true
            r.revision = snapshot.revision
            let operations = session.operations(snapshot)
            r.defaults = DefaultInfo(operations)
            let browsers = session.context.browsers
            for path in snapshot.config.browsers {
                let info = browsers.at(path)
                var check = BrowserCheck(path: path, name: browsers.displayName(path), installed: info != nil)
                check.localState = info.flatMap {
                    $0.family.isChromium ? $0.userData.appendingPathComponent("Local State").path : nil
                }
                do {
                    check.profileCount = try Profiles.of(browsers, path).count
                } catch {
                    check.error = error.description
                }
                r.browsers.append(check)
            }
            for rule in operations.rules() {
                func problem(_ kind: String, _ message: String) {
                    r.rules.append(
                        RuleProblem(
                            index: rule.index, condition: rule.condition, value: rule.value, problem: kind,
                            message: message))
                }
                if rule.value.isEmpty {
                    problem("empty_pattern", "The pattern is empty, so the rule never matches.")
                }
                if let message = Format.problem(rule.profileStatus, rule.destination) {
                    problem("profile_\(rule.profileStatus.rawValue)", message)
                }
                if let by = rule.shadowedBy {
                    problem("unreachable", "Never matches: rule \(by) always matches first.")
                }
            }
            r.historyEnabled = snapshot.config.historyEnabled
        } catch {
            r.configError = error.description
            r.revision = try? store.currentRevision()
        }
        let history = session.history
        do {
            r.historyEntries = try history.entries().count
        } catch {
            r.historyError = error.message
        }
        r.lastWriteError = history.lastWriteError
        r.ok =
            r.configValid && r.defaults?.profileStatus == .ok && r.rules.isEmpty
            && r.browsers.allSatisfy { $0.error == nil }
            && r.historyError == nil && r.lastWriteError == nil
        return Output(json: r.json, text: r.text)
    }
}

private struct BrowserCheck {
    var path: String
    var name: String
    var installed: Bool
    var localState: String?
    var profileCount: Int?
    var error: String?
}

private struct RuleProblem {
    var index: Int
    var condition: Condition
    var value: String
    /// empty_pattern, profile_missing, profile_ambiguous, profile_unavailable, or unreachable.
    var problem: String
    var message: String
}

private struct DoctorReport {
    var ok = false
    var configPath: String
    var configExists: Bool
    var configValid = false
    var revision: String?
    var configError: String?
    var defaults: DefaultInfo?
    var browsers: [BrowserCheck] = []
    var rules: [RuleProblem] = []
    var historyPath: String
    var historyEnabled = true
    var historyEntries: Int?
    var historyError: String?
    var lastWriteError: String?

    var json: JSONObject {
        var config = JSONObject()
        config.set("path", configPath)
        config.set("exists", configExists)
        config.set("valid", configValid)
        config.set("revision", revision)
        config.setIfPresent("error", configError)
        var history = JSONObject()
        history.set("path", historyPath)
        history.set("enabled", historyEnabled)
        history.set("entries", historyEntries)
        history.setIfPresent("error", historyError)
        history.set("lastWriteError", lastWriteError)
        var report = JSONObject()
        report.set("ok", ok)
        report.set("config", config)
        report.setIfPresent("default", defaults)
        report.set(
            "browsers",
            browsers.map { b -> JSONObject in
                var o = JSONObject()
                o.set("path", b.path)
                o.set("name", b.name)
                o.set("installed", b.installed)
                o.set("localState", b.localState)
                o.set("profileCount", b.profileCount)
                o.setIfPresent("error", b.error)
                return o
            })
        report.set(
            "rules",
            rules.map { p -> JSONObject in
                var o = JSONObject()
                o.set("index", p.index)
                o.set("condition", p.condition)
                o.set("value", p.value)
                o.set("problem", p.problem)
                o.set("message", p.message)
                return o
            })
        report.set("history", history)
        report.set("version", cliVersion)
        return report
    }

    var text: String {
        func line(_ ok: Bool, _ message: String) -> String { "  \(ok ? "✓" : "!") \(message)\n" }
        var text = "Configuration: \(configPath)\n"
        if let configError {
            text += line(false, configError)
        } else {
            let state = configExists ? "valid" : "not created yet; using defaults"
            text += line(true, state + (revision.map { ", revision \(Format.short($0))" } ?? ""))
        }
        if let d = defaults {
            text += "Default: \(d.destination.label)\n"
            text += line(
                d.profileStatus == .ok, Format.problem(d.profileStatus, d.destination) ?? "profile resolves")
        }
        if !browsers.isEmpty { text += "Browsers:\n" }
        for b in browsers {
            let detail =
                b.error ?? "\(b.profileCount ?? 0) profiles"
                + (b.localState.map { ", Local State at \($0)" } ?? "")
            text += line(b.error == nil, "\(b.name)  \(b.path)  \(detail)")
        }
        if configValid {
            text += "Rules:\n"
            if rules.isEmpty { text += line(true, "every rule resolves and can match") }
            for p in rules {
                text += line(false, "rule \(p.index) (\(p.condition.rawValue) \(p.value)): \(p.message)")
            }
        }
        text += "History: \(historyPath)\n"
        let entries = historyEntries ?? 0
        text += line(
            historyError == nil,
            historyError
                ?? "\(historyEnabled ? "on" : "off"), \(entries) \(entries == 1 ? "entry" : "entries")")
        if let lastWriteError { text += line(false, "last write failed: \(lastWriteError)") }
        text += "Version: \(cliVersion)\n"
        text += ok ? "No problems found.\n" : "Problems found; see the ! lines above.\n"
        return text
    }
}
