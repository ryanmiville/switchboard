import ArgumentParser
import Foundation

struct DoctorCommand: RunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check the configuration, browsers, profiles, history, and versions. Changes nothing.")

    @OptionGroup var global: GlobalOptions

    func run(in context: CommandContext) throws -> CommandOutput {
        let session = Session(context, global)
        var report = DoctorReport(
            config: .init(
                path: session.configURL.path,
                exists: FileManager.default.fileExists(atPath: session.configURL.path)),
            history: .init(path: session.historyURL.path, enabled: true),
            version: .init(
                cli: CommandLineTool.bundleVersion(executable: context.executableURL),
                app: CommandLineTool.appVersion(context.installedApp), appPath: context.installedApp.path))
        var snapshot: ConfigStore.Snapshot?
        do {
            snapshot = try session.store.load()
            report.config.valid = true
            report.config.revision = snapshot?.revision
        } catch {
            report.config.error = error.localizedDescription
            report.config.revision = try? session.store.currentRevision()
        }
        if let snapshot {
            let operations = session.operations(snapshot)
            let fallback = operations.describe(operations.defaultDestination)
            report.default = DefaultInfo(destination: fallback.info, profileStatus: fallback.status)
            var seen = Set<String>()
            for path in [snapshot.config.browser] + snapshot.config.routes.compactMap(\.browser)
            where seen.insert(path).inserted {
                var check = DoctorReport.Browser(
                    path: path, name: BrowserInfo.displayName(path: path),
                    installed: BrowserInfo(path: path) != nil,
                    localState: operations.catalog.profileStore.localStateURL(browserPath: path)?.path)
                do {
                    check.profileCount = try operations.profiles.profiles(in: path).count
                } catch {
                    check.error = error.localizedDescription
                }
                report.browsers.append(check)
            }
            for rule in operations.rules() {
                func problem(_ kind: String, _ message: String) {
                    report.rules.append(
                        .init(
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
            report.history.enabled = snapshot.config.historyEnabled
        }
        do {
            report.history.entries = try session.history.entries().count
        } catch {
            report.history.error = error.localizedDescription
        }
        report.history.lastWriteError = session.history.lastWriteError()
        if let cli = report.version.cli, let app = report.version.app { report.version.matches = cli == app }
        report.ok =
            report.config.valid && report.default?.profileStatus == .ok && report.rules.isEmpty
            && report.browsers.allSatisfy { $0.error == nil } && report.history.error == nil
            && report.history.lastWriteError == nil && report.version.matches != false
        return CommandOutput(json: report, text: text(report))
    }

    private func text(_ report: DoctorReport) -> String {
        func line(_ ok: Bool, _ message: String) -> String { "  \(ok ? "✓" : "!") \(message)\n" }
        var text = "Configuration: \(report.config.path)\n"
        if let error = report.config.error {
            text += line(false, error)
        } else {
            text += line(
                true,
                (report.config.exists ? "valid" : "not created yet; using defaults")
                    + (report.config.revision.map { ", revision \(Format.short($0))" } ?? ""))
        }
        if let fallback = report.default {
            text += "Default: \(Format.destination(fallback.destination))\n"
            text += line(
                fallback.profileStatus == .ok,
                Format.problem(fallback.profileStatus, fallback.destination) ?? "profile resolves")
        }
        if !report.browsers.isEmpty { text += "Browsers:\n" }
        for browser in report.browsers {
            let detail =
                browser.error
                ?? "\(browser.profileCount ?? 0) profiles, Local State at \(browser.localState ?? "unknown")"
            text += line(browser.error == nil, "\(browser.name)  \(browser.path)  \(detail)")
        }
        if report.config.valid {
            text += "Rules:\n"
            if report.rules.isEmpty { text += line(true, "every rule resolves and can match") }
            for problem in report.rules {
                text += line(
                    false,
                    "rule \(problem.index) (\(problem.condition.rawValue) \(problem.value)): \(problem.message)"
                )
            }
        }
        text += "History: \(report.history.path)\n"
        text += line(
            report.history.error == nil,
            report.history.error
                ?? "\(report.history.enabled ? "on" : "off"), \(report.history.entries ?? 0) \(report.history.entries == 1 ? "entry" : "entries")"
        )
        if let error = report.history.lastWriteError { text += line(false, "last write failed: \(error)") }
        text += "Version:\n"
        switch (report.version.cli, report.version.app) {
        case (let cli?, let app?):
            text += line(
                cli == app,
                cli == app
                    ? "switchboard \(cli) matches \(report.version.appPath)"
                    : "switchboard \(cli) differs from \(report.version.appPath) \(app). Reinstall with `make install-cli`."
            )
        case (nil, let app?):
            text += line(true, "development build; \(report.version.appPath) is \(app)")
        case (_, nil):
            text += line(true, "no app at \(report.version.appPath)")
        }
        text += report.ok ? "No problems found.\n" : "Problems found; see the ! lines above.\n"
        return text
    }
}

struct DoctorReport: Encodable {
    struct Configuration: Encodable {
        var path: String
        var exists: Bool
        var valid = false
        var revision: String? = nil
        var error: String? = nil
    }

    struct Browser: Encodable {
        var path: String
        var name: String
        var installed: Bool
        var localState: String?
        var profileCount: Int? = nil
        var error: String? = nil
    }

    struct RuleProblem: Encodable {
        var index: Int
        var condition: Condition
        var value: String
        // empty_pattern, profile_missing, profile_ambiguous, profile_unavailable, or unreachable.
        var problem: String
        var message: String
    }

    struct History: Encodable {
        var path: String
        var enabled: Bool
        var entries: Int? = nil
        var error: String? = nil
        var lastWriteError: String? = nil
    }

    struct Version: Encodable {
        // nil when the CLI isn't running from an app bundle.
        var cli: String?
        var app: String?
        var appPath: String
        var matches: Bool? = nil
    }

    var ok = false
    var config: Configuration
    var `default`: DefaultInfo? = nil
    var browsers: [Browser] = []
    var rules: [RuleProblem] = []
    var history: History
    var version: Version
}
