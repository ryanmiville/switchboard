import Foundation
import Testing

@testable import SwitchboardCore

// Runs commands in-process with fixture files. Every run passes --config and --history-file.
struct CLITests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    struct Setup {
        let fixture: Fixture
        let chrome: String
        let helium: String
    }

    private func setUp(routes: [Route] = [], history: [HistoryEntry] = []) throws -> Setup {
        let fixture = try Fixture()
        let chrome = try fixture.browser(name: "Google Chrome", bundleName: "Chrome").path
        let helium = try fixture.browser(id: "net.imput.helium", name: "Helium").path
        try fixture.profiles(["Default": "Personal", "Profile 2": "Work"])
        try fixture.profiles(["Default": "Ryan", "Profile 1": "H3"], folder: "net.imput.helium")
        try Config(browser: helium, defaultProfile: "Default", routes: routes).save(to: fixture.configURL)
        let store = HistoryStore(url: fixture.historyURL)
        for entry in history { try store.append(entry) }
        return Setup(fixture: fixture, chrome: chrome, helium: helium)
    }

    private func context(_ fixture: Fixture, environment: [String: String] = [:]) -> CommandContext {
        CommandContext(
            environment: environment, homeDirectory: fixture.root, applicationDirectories: [fixture.root],
            executableURL: nil, installedApp: fixture.root.appendingPathComponent("Switchboard.app"),
            now: Self.now)
    }

    private func run(_ setup: Setup, _ arguments: [String]) -> CommandLineTool.Outcome {
        CommandLineTool.run(
            arguments + [
                "--config", setup.fixture.configURL.path, "--history-file", setup.fixture.historyURL.path,
            ],
            context: context(setup.fixture))
    }

    private func json(_ outcome: CommandLineTool.Outcome) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(outcome.stdout.utf8)) as? [String: Any])
    }

    private func error(_ outcome: CommandLineTool.Outcome) throws -> [String: Any] {
        try #require(try json(outcome)["error"] as? [String: Any])
    }

    private func entry(_ url: String, id: String, browser: String, minutesAgo: Double = 2) -> HistoryEntry {
        HistoryEntry(
            id: id, time: Self.now.addingTimeInterval(-60 * minutesAgo), url: url, source: .default,
            browser: browser, profile: "Default", profileName: "Ryan", result: .launched)
    }

    @Test func explainReportsTheMatchedRuleDestinationAndShadowedMatches() throws {
        let setup = try setUp(routes: [
            Route(condition: .domain, value: "github.com", profile: "Profile 1"),
            Route(
                condition: .contains, value: "acme", profile: "Profile 2", browser: "/unused/placeholder.app"),
        ])
        defer { setup.fixture.cleanUp() }
        let outcome = run(setup, ["explain", "https://github.com/acme/api/pull/12", "--json"])
        #expect(outcome.status == 0)
        let report = try json(outcome)
        #expect(
            Set(report.keys) == [
                "url", "matchedRule", "destination", "profileStatus", "alsoMatches", "revision",
            ])
        #expect(report["url"] as? String == "https://github.com/acme/api/pull/12")
        let rule = try #require(report["matchedRule"] as? [String: Any])
        #expect(rule["index"] as? Int == 1)
        #expect(rule["condition"] as? String == "domain")
        #expect(rule["value"] as? String == "github.com")
        let destination = try #require(report["destination"] as? [String: Any])
        #expect(destination["browser"] as? String == setup.helium)
        #expect(destination["browserName"] as? String == "Helium")
        #expect(destination["profile"] as? String == "Profile 1")
        #expect(destination["profileName"] as? String == "H3")
        #expect(report["profileStatus"] as? String == "ok")
        #expect((report["alsoMatches"] as? [[String: Any]])?.first?["index"] as? Int == 2)
        #expect(report["revision"] as? String == SHA256.hex(try Data(contentsOf: setup.fixture.configURL)))

        let unmatched = try json(run(setup, ["explain", "https://example.com", "--json"]))
        #expect(unmatched["matchedRule"] is NSNull)
        let text = run(setup, ["explain", "https://github.com/acme"]).stdout
        #expect(text.contains("Rule 1 matched: domain github.com"))
        #expect(text.contains("→ Helium · H3 (Profile 1)"))
        #expect(text.contains("Also matches, but never reached: rule 2 (contains acme)"))
    }

    @Test func routePreviewsWritesAndIsConfirmedByExplain() throws {
        let setup = try setUp(history: [
            entry(
                "https://github.com/acme/api/pull/12?token=secret", id: "a41f9c02",
                browser: "/Applications/Helium.app")
        ])
        defer { setup.fixture.cleanUp() }
        let original = try Data(contentsOf: setup.fixture.configURL)
        let preview = run(
            setup, ["route", "--last", "--profile", "Work", "--browser", "Chrome", "--dry-run", "--json"])
        #expect(preview.status == 0)
        let planned = try json(preview)
        #expect(planned["changed"] as? Bool == true)
        #expect(planned["written"] as? Bool == false)
        #expect(planned["action"] as? String == "added")
        #expect(planned["url"] as? String == "https://github.com/acme/api/pull/12?…")
        #expect((planned["before"] as? [String: Any])?["rule"] is NSNull)
        #expect(((planned["after"] as? [String: Any])?["rule"] as? [String: Any])?["index"] as? Int == 1)
        #expect((planned["rule"] as? [String: Any])?["browser"] as? String == setup.chrome)
        #expect(try Data(contentsOf: setup.fixture.configURL) == original)
        let revision = try #require(planned["revision"] as? String)

        let applied = run(
            setup,
            ["route", "--last", "--profile", "Profile 2", "--browser", "Chrome", "--if-revision", revision])
        #expect(applied.status == 0)
        #expect(applied.stdout.contains("Added rule 1: domain github.com → Google Chrome · Work (Profile 2)"))
        #expect(applied.stdout.contains("before: Helium · Ryan (Default)  [default]"))
        #expect(!applied.stdout.contains("secret"))
        let saved = try Config.load(from: setup.fixture.configURL)
        #expect(saved.routes.map(\.value) == ["github.com"])
        #expect(saved.routes.first?.browser == setup.chrome)

        let confirmed = run(setup, ["explain", "--history", "9c02"])
        #expect(confirmed.stdout.contains("Rule 1 matched: domain github.com"))
        #expect(confirmed.stdout.contains("At the time (2m ago): default → Helium · Ryan, launched"))
        #expect(!confirmed.stdout.contains("secret"))
        let again = try json(
            run(setup, ["route", "--last", "--profile", "Work", "--browser", "Chrome", "--json"]))
        #expect(again["changed"] as? Bool == false)
        #expect(again["action"] as? String == "unchanged")
    }

    @Test func staleRevisionsExitFiveWithoutWriting() throws {
        let setup = try setUp()
        defer { setup.fixture.cleanUp() }
        let original = try Data(contentsOf: setup.fixture.configURL)
        let outcome = run(
            setup,
            [
                "route", "https://github.com", "--profile", "H3", "--if-revision",
                String(repeating: "0", count: 64), "--json",
            ])
        #expect(outcome.status == 5)
        #expect(try error(outcome)["code"] as? String == "conflict")
        #expect(try Data(contentsOf: setup.fixture.configURL) == original)
        #expect(run(setup, ["rules", "remove", "1", "--if-revision", "abc"]).status == 64)
    }

    @Test func unknownNamesExitThreeWithCandidatesAndChangeNothing() throws {
        let setup = try setUp()
        defer { setup.fixture.cleanUp() }
        let original = try Data(contentsOf: setup.fixture.configURL)
        let profile = run(
            setup, ["route", "https://github.com", "--profile", "Nobody", "--browser", "Chrome", "--json"])
        #expect(profile.status == 3)
        let body = try error(profile)
        #expect(body["code"] as? String == "profile_not_found")
        let candidates = try #require(body["candidates"] as? [[String: Any]])
        #expect(candidates.compactMap { $0["profile"] as? String } == ["Default", "Profile 2"])
        #expect(candidates.first?["browser"] as? String == setup.chrome)
        let browser = run(
            setup, ["route", "https://github.com", "--profile", "Work", "--browser", "Firefox"])
        #expect(browser.status == 3)
        #expect(browser.stderr.hasPrefix("error: No installed browser matches “Firefox”."))
        #expect(browser.stderr.contains("Google Chrome  \(setup.chrome)  (com.google.Chrome)"))
        #expect(run(setup, ["rules", "update", "4", "--profile", "H3"]).status == 3)
        #expect(run(setup, ["explain", "--last"]).status == 3)
        #expect(try Data(contentsOf: setup.fixture.configURL) == original)
    }

    @Test func unreadableConfigurationExitsFourAndIsLeftUntouched() throws {
        let setup = try setUp()
        defer { setup.fixture.cleanUp() }
        let original = Data(#"{"browser": "/Applications/Helium.app", "routes": []}"#.utf8)
        try original.write(to: setup.fixture.configURL)
        let list = run(setup, ["rules", "list", "--json"])
        #expect(list.status == 4)
        #expect(try error(list)["code"] as? String == "config_invalid")
        #expect(try (error(list)["message"] as? String)?.contains("defaultProfile") == true)
        #expect(run(setup, ["route", "https://github.com", "--profile", "H3"]).status == 4)
        #expect(try Data(contentsOf: setup.fixture.configURL) == original)
        let doctor = try json(run(setup, ["doctor", "--json"]))
        #expect(doctor["ok"] as? Bool == false)
        #expect((doctor["config"] as? [String: Any])?["valid"] as? Bool == false)
    }

    @Test func invalidCommandLinesExitSixtyFour() throws {
        let setup = try setUp()
        defer { setup.fixture.cleanUp() }
        let missing = run(setup, ["route", "https://github.com"])
        #expect(missing.status == 64)
        #expect(missing.stderr.contains("--profile"))
        let both = run(setup, ["explain", "https://github.com", "--last", "--json"])
        #expect(both.status == 64)
        #expect(try error(both)["code"] as? String == "invalid_argument")
        #expect(run(setup, ["explain", "github.com"]).status == 64)
        #expect(run(setup, ["rules", "update", "1", "--browser", "Chrome"]).status == 64)
        #expect(
            run(setup, ["route", "https://github.com", "--profile", "H3", "--match", "regex"]).status == 64)
        let help = run(setup, ["route", "--help"])
        #expect(help.status == 0)
        #expect(help.stdout.contains("--allow-shadowing"))
    }

    @Test func historyHidesQueryStringsUnlessAsked() throws {
        let setup = try setUp(history: [
            entry(
                "https://accounts.example.com/callback?code=secret", id: "7d02be11",
                browser: "/Applications/Helium.app", minutesAgo: 60),
            entry("https://github.com/acme/api/pull/12", id: "a41f9c02", browser: "/Applications/Helium.app"),
        ])
        defer { setup.fixture.cleanUp() }
        let text = run(setup, ["history", "--limit", "5"])
        #expect(text.status == 0)
        let lines = text.stdout.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.first?.hasPrefix("a41f9c02  2m ago") == true)
        #expect(lines.last?.contains("https://accounts.example.com/callback?…") == true)
        #expect(lines.last?.contains("default → Helium · Ryan") == true)
        #expect(!text.stdout.contains("secret"))
        let report = try json(run(setup, ["history", "--limit", "1", "--json"]))
        let entries = try #require(report["entries"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries.first?["id"] as? String == "a41f9c02")
        let full = run(setup, ["history", "list", "--full-urls"])
        #expect(full.stdout.contains("code=secret"))
        let explained = try json(run(setup, ["explain", "--history", "7d02", "--json"]))
        #expect(explained["url"] as? String == "https://accounts.example.com/callback?…")
        #expect((explained["history"] as? [String: Any])?["source"] as? String == "default")
        #expect(run(setup, ["explain", "--history", "02", "--json"]).status == 64)
        #expect(run(setup, ["explain", "--history", "ffff"]).status == 3)
    }

    @Test func turnedOffHistoryIsReportedButCanStillBeCleared() throws {
        let setup = try setUp(history: [
            entry("https://github.com", id: "a41f9c02", browser: "/Applications/Helium.app")
        ])
        defer { setup.fixture.cleanUp() }
        var config = try Config.load(from: setup.fixture.configURL)
        config.history = HistorySettings(enabled: false)
        try config.save(to: setup.fixture.configURL)
        let list = run(setup, ["history", "--json"])
        #expect(list.status == 1)
        #expect(try error(list)["code"] as? String == "history_disabled")
        #expect(run(setup, ["explain", "--last"]).status == 1)
        let preview = try json(run(setup, ["history", "clear", "--dry-run", "--json"]))
        #expect(preview["entries"] as? Int == 1)
        #expect(FileManager.default.fileExists(atPath: setup.fixture.historyURL.path))
        let cleared = run(setup, ["history", "clear"])
        #expect(cleared.stdout == "Cleared 1 history entry.\n")
        #expect(!FileManager.default.fileExists(atPath: setup.fixture.historyURL.path))
    }

    @Test func ruleCommandsEditByPositionAndReportAffectedLinks() throws {
        let setup = try setUp(
            routes: [
                Route(condition: .domain, value: "github.com", profile: "Default"),
                Route(condition: .contains, value: "acme", profile: "Profile 1"),
                Route(condition: .domain, value: "youtube.com", profile: "H3"),
            ],
            history: [
                entry("https://github.com/acme/api", id: "a41f9c02", browser: "/Applications/Helium.app")
            ])
        defer { setup.fixture.cleanUp() }
        let list = try json(run(setup, ["rules", "--json"]))
        let rules = try #require(list["rules"] as? [[String: Any]])
        #expect(rules.map { $0["index"] as? Int } == [1, 2, 3])
        #expect(rules[0]["browser"] is NSNull)
        #expect(rules[2]["profile"] as? String == "H3")
        #expect((rules[2]["destination"] as? [String: Any])?["profile"] as? String == "Profile 1")
        #expect(rules.map { $0["profileStatus"] as? String } == ["ok", "ok", "ok"])
        #expect(
            ((list["default"] as? [String: Any])?["destination"] as? [String: Any])?["profileName"] as? String
                == "Ryan")
        let revision = try #require(list["revision"] as? String)

        let moved = try json(run(setup, ["rules", "move", "2", "1", "--if-revision", revision, "--json"]))
        #expect(moved["action"] as? String == "moved")
        #expect(moved["from"] as? Int == 2)
        #expect(moved["to"] as? Int == 1)
        let changes = try #require(moved["historyChanges"] as? [[String: Any]])
        #expect(changes.map { $0["id"] as? String } == ["a41f9c02"])
        #expect(
            try Config.load(from: setup.fixture.configURL).routes.map(\.value) == [
                "acme", "github.com", "youtube.com",
            ])

        let updated = run(setup, ["rules", "update", "3", "--browser", "Chrome", "--profile", "Work"])
        #expect(updated.status == 0)
        #expect(
            updated.stdout.contains("Updated rule 3: domain youtube.com → Google Chrome · Work (Profile 2)"))
        #expect(updated.stdout.contains("was: domain youtube.com → Helium · H3 (Profile 1)"))
        let removed = try json(run(setup, ["rules", "remove", "1", "--dry-run", "--json"]))
        #expect(removed["written"] as? Bool == false)
        #expect((removed["rule"] as? [String: Any])?["value"] as? String == "acme")
        #expect(try Config.load(from: setup.fixture.configURL).routes.count == 3)
        let shadow = run(setup, ["rules", "update", "2", "--value", "com", "--json"])
        #expect(shadow.status == 1)
        #expect(try error(shadow)["code"] as? String == "would_shadow")
    }

    @Test func defaultChangesWaitForRulesThatInheritTheBrowser() throws {
        let setup = try setUp(routes: [Route(condition: .domain, value: "youtube.com", profile: "Profile 1")])
        defer { setup.fixture.cleanUp() }
        let shown = try json(run(setup, ["default", "--json"]))
        #expect((shown["destination"] as? [String: Any])?["profileName"] as? String == "Ryan")
        let refused = run(setup, ["default", "--browser", "Chrome", "--profile", "Work", "--json"])
        #expect(refused.status == 3)
        let body = try error(refused)
        #expect(body["code"] as? String == "inheriting_rules")
        let suggestion = try #require(
            (body["candidates"] as? [[String: Any]])?.first?["suggestion"] as? String)
        #expect(suggestion.hasPrefix("switchboard rules update 1 --browser "))
        #expect(
            run(setup, ["rules", "update", "1", "--browser", setup.helium, "--profile", "Profile 1"]).status
                == 0)
        let changed = try json(run(setup, ["default", "--browser", "Chrome", "--profile", "Work", "--json"]))
        #expect(changed["written"] as? Bool == true)
        #expect((changed["destination"] as? [String: Any])?["browser"] as? String == setup.chrome)
        let saved = try Config.load(from: setup.fixture.configURL)
        #expect(saved.browser == setup.chrome)
        #expect(saved.defaultProfile == "Profile 2")
        #expect(saved.routes.first?.browser == setup.helium)
    }

    @Test func profilesListsBrowsersWithDirectoriesAndNames() throws {
        let setup = try setUp()
        defer { setup.fixture.cleanUp() }
        let report = try json(run(setup, ["profiles", "--json"]))
        let browsers = try #require(report["browsers"] as? [[String: Any]])
        #expect(browsers.map { $0["name"] as? String } == ["Google Chrome", "Helium"])
        #expect(browsers.map { $0["isDefault"] as? Bool } == [false, true])
        let profiles = try #require(browsers.first?["profiles"] as? [[String: Any]])
        #expect(profiles.map { $0["profile"] as? String } == ["Default", "Profile 2"])
        #expect(profiles.map { $0["profileName"] as? String } == ["Personal", "Work"])
        let one = run(setup, ["profiles", "--browser", "net.imput.helium"])
        #expect(one.stdout.hasPrefix("Helium (default browser)  \(setup.helium)"))
        #expect(one.stdout.contains("Profile 1  H3"))
    }

    @Test func doctorReportsMissingProfilesAndUnreachableRules() throws {
        let setup = try setUp(routes: [
            Route(condition: .domain, value: "github.com", profile: "Profile 9"),
            Route(condition: .domain, value: "docs.github.com", profile: "Default"),
            Route(condition: .contains, value: "", profile: "Default"),
        ])
        defer { setup.fixture.cleanUp() }
        let outcome = run(setup, ["doctor", "--json"])
        #expect(outcome.status == 0)
        let report = try json(outcome)
        #expect(report["ok"] as? Bool == false)
        let problems = try #require(report["rules"] as? [[String: Any]])
        #expect(
            problems.map { $0["problem"] as? String } == ["profile_missing", "unreachable", "empty_pattern"])
        #expect(problems.map { $0["index"] as? Int } == [1, 2, 3])
        let browsers = try #require(report["browsers"] as? [[String: Any]])
        #expect(browsers.first?["profileCount"] as? Int == 2)
        #expect((report["history"] as? [String: Any])?["enabled"] as? Bool == true)
        #expect((report["version"] as? [String: Any])?["cli"] == nil)
    }

    @Test func environmentVariablesChooseTheFiles() throws {
        let setup = try setUp(routes: [Route(condition: .domain, value: "github.com", profile: "Profile 1")])
        defer { setup.fixture.cleanUp() }
        let outcome = CommandLineTool.run(
            ["rules", "list"],
            context: context(
                setup.fixture,
                environment: [
                    "SWITCHBOARD_CONFIG": setup.fixture.configURL.path,
                    "SWITCHBOARD_HISTORY": setup.fixture.historyURL.path,
                ]))
        #expect(outcome.stdout.contains("github.com"))
        // Without either, the configuration comes from the (fixture) home directory.
        let home = CommandLineTool.run(["rules", "list", "--json"], context: context(setup.fixture))
        #expect(try (json(home)["rules"] as? [Any])?.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: Config.path(home: setup.fixture.root).path))
    }

    @Test func bundledToolsReadTheirAppVersion() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let app = fixture.root.appendingPathComponent("Switchboard.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/Helpers"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "7"], format: .xml,
            options: 0
        ).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let tool = app.appendingPathComponent("Contents/Helpers/switchboard")
        #expect(CommandLineTool.bundleVersion(executable: tool) == "1.2 (7)")
        #expect(
            CommandLineTool.bundleVersion(executable: fixture.root.appendingPathComponent("switchboard"))
                == nil)
        let outcome = CommandLineTool.run(
            [
                "doctor", "--json", "--config", fixture.configURL.path, "--history-file",
                fixture.historyURL.path,
            ],
            context: CommandContext(
                environment: [:], homeDirectory: fixture.root, applicationDirectories: [],
                executableURL: tool,
                installedApp: app))
        let version = try #require(try json(outcome)["version"] as? [String: Any])
        #expect(version["matches"] as? Bool == true)
    }
}
