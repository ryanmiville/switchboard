import Foundation
import SwiftUI
import SwitchboardCore
import SwitchboardEditor
import SwitchboardFixtures

/// Named starting states for headless renders (`Switchboard --snap --scene <name>`), tests and
/// goldens. Each starts from a fresh `SceneHome`, so renders never read the real home. Add a scene
/// for every new pane or state.
@MainActor
public enum Scenes {
    public struct Scene: Sendable {
        public let name: String
        let kind: Kind
        let setup: @MainActor @Sendable (SettingsModel, PickerModel, SceneHome) throws -> Void
    }

    enum Kind: Sendable { case settings, ruleSheet, picker }

    /// A scene ready to draw, with the temporary home it reads. Call `remove()` when done.
    public struct Instance {
        public let view: AnyView
        public let size: CGSize
        public let settings: SettingsModel
        public let picker: PickerModel
        let home: SceneHome

        public func remove() { home.remove() }
    }

    public nonisolated static let all: [Scene] = [
        Scene(name: "general", kind: .settings) { _, _, _ in },
        Scene(name: "login-approval", kind: .settings) { _, _, _ in },
        Scene(name: "not-default-browser", kind: .settings) { _, _, _ in },
        Scene(name: "default-browser-error", kind: .settings) { s, _, _ in s.makeDefaultBrowser() },
        Scene(name: "no-default-browser", kind: .settings) { s, _, _ in
            s.editor.edit { $0.browser = "" }
            s.editor.refreshProfiles()
        },
        Scene(name: "routing", kind: .settings) { s, _, _ in s.pane = .routing },
        Scene(name: "routing-selected", kind: .settings) { s, _, _ in
            s.pane = .routing
            s.selected = s.editor.config.rules[1].id
        },
        Scene(name: "routing-test", kind: .settings) { s, _, _ in
            s.pane = .routing
            s.testURL = "https://github.com/acme/api"
        },
        Scene(name: "routing-empty", kind: .settings) { s, _, _ in
            s.pane = .routing
            s.editor.edit { $0.rules.removeAll() }
            s.editor.flush()
        },
        Scene(name: "missing-profile", kind: .settings) { s, _, _ in
            s.pane = .routing
            s.editor.edit { $0.rules[0].profile = "Profile 9" }
            s.editor.refreshProfiles()
        },
        Scene(name: "rule-new", kind: .ruleSheet) { s, _, _ in s.draft = .newRule() },
        Scene(name: "rule-edit", kind: .ruleSheet) { s, _, _ in s.draft = .editing(s.editor.config.rules[1])
        },
        Scene(name: "rule-error", kind: .ruleSheet) { s, _, _ in
            var draft = Draft.newRule()
            draft.value = "github.com/acme"
            draft.profile = "Default"
            _ = draft.validated()
            s.draft = draft
        },
        Scene(name: "conflict", kind: .settings) { s, _, home in
            s.editor.selectDefaultProfile("Profile 1")
            try Data(#"{"browser":"\#(home.helium)","defaultProfile":"Default"}"#.utf8).write(
                to: home.home.configFile)
            s.editor.checkExternal()
        },
        Scene(name: "load-error", kind: .settings) { s, _, home in
            try Data(#"{"browser": "#.utf8).write(to: home.home.configFile)
            s.editor.reload()
        },
        Scene(name: "link-failure", kind: .settings) { s, _, _ in
            s.pane = .routing
            s.failure = Failure(
                url: "https://github.com/acme/api/pull/12",
                reason: "The profile “Profile 9” is unavailable. Choose an existing profile.")
        },
        Scene(name: "recent", kind: .settings) { s, _, home in
            s.pane = .recent
            try Scenes.recordLinks(home)
            s.reloadRecent()
        },
        Scene(name: "recent-empty", kind: .settings) { s, _, _ in s.pane = .recent },
        Scene(name: "recent-history-off", kind: .settings) { s, _, home in
            s.pane = .recent
            try Scenes.recordLinks(home)
            s.editor.edit { $0.history = HistorySettings(enabled: false) }
            s.editor.flush()
            s.reloadRecent()
        },
        Scene(name: "recent-add-rule", kind: .ruleSheet) { s, _, home in
            try Scenes.recordLinks(home)
            s.reloadRecent()
            if let entry = s.editor.recent.first(where: { $0.source == .picker }) { s.addRule(for: entry) }
        },
        Scene(name: "quick-switch", kind: .settings) { s, _, _ in s.pane = .quickSwitch },
        // Summoned over Helium's Ryan profile, which the list leaves out.
        Scene(name: "picker", kind: .picker) { _, p, home in Scenes.fromRyan(p, home) },
        Scene(name: "picker-search", kind: .picker) { _, p, home in
            Scenes.fromRyan(p, home)
            p.query = "work"
        },
        Scene(name: "picker-numbers", kind: .picker) { _, p, home in
            Scenes.fromRyan(p, home)
            p.showsNumbers = true
        },
        Scene(name: "picker-permission", kind: .picker) { _, p, _ in
            p.state.link = ""
            p.tabRead(.failure(.automationDenied), browserID: nil)
        },
        Scene(name: "picker-unavailable-favorite", kind: .picker) { _, p, home in
            p.state.settings.favorites.append(
                Favorite(browser: home.helium, profile: "Profile 9", name: "Old work"))
            p.state.all = QuickSwitch.choices(home.browsers.installed(), p.state.settings)
        },
        Scene(name: "picker-empty", kind: .picker) { _, p, _ in p.state.settings.destinations = [] },
    ]

    public nonisolated static var names: [String] { all.map(\.name) }

    /// The panel as summoned over a Helium window of the Ryan profile.
    @MainActor
    static func fromRyan(_ picker: PickerModel, _ home: SceneHome) {
        let helium = home.browsers.installed().first { $0.locator == home.helium }?.id
        picker.tabRead(
            .success(
                BrowserTab(
                    link: "https://github.com/acme/api/pull/12",
                    windowTitle: "Pull request #12 - Helium - Ryan")),
            browserID: helium)
    }

    /// Five links in history, as the scene home's rules sent them, the newest two minutes before
    /// `SettingsServices.sceneTime`.
    static func recordLinks(_ home: SceneHome) throws {
        func entry(
            minutesAgo: Int64, _ url: String, _ source: History.Source, rule: History.RuleSnapshot? = nil,
            _ browser: String, _ profile: String, _ name: String, error: String? = nil
        ) -> History.Entry {
            History.Entry(
                id: History.newID(),
                time: Timestamp(SettingsServices.sceneTime.seconds - minutesAgo * 60).rfc3339,
                url: url, source: source, rule: rule, browser: browser, profile: profile, profileName: name,
                result: error == nil ? .launched : .failed, error: error)
        }
        let oldestFirst = [
            entry(
                minutesAgo: 26 * 60, "https://example.com/login", .rule,
                rule: History.RuleSnapshot(index: 4, condition: .exact, value: "https://example.com/login"),
                home.chrome, "Profile 3", "Side project",
                error: LaunchError.spawn("Operation not permitted").description),
            entry(
                minutesAgo: 3 * 60, "https://www.figma.com/file/k2Jd/roadmap", .picker, home.chrome,
                "Profile 3", "Side project"),
            entry(
                minutesAgo: 62, "https://news.ycombinator.com/item?id=41234567", .default, home.helium,
                "Default", "Ryan"),
            entry(
                minutesAgo: 14, "https://acme.atlassian.net/browse/OPS-7?focusedCommentId=1", .rule,
                rule: History.RuleSnapshot(index: 2, condition: .contains, value: "acme"),
                home.chrome, "Profile 2", "Work"),
            entry(
                minutesAgo: 2, "https://github.com/acme/api/pull/12", .rule,
                rule: History.RuleSnapshot(index: 1, condition: .domain, value: "github.com"),
                home.helium, "Profile 1", "Work"),
        ]
        for link in oldestFirst { try home.temporary.historyStore.append(link) }
    }

    /// Builds the scene named `name` over a fresh fixture home.
    public static func make(_ name: String) throws -> Instance {
        guard let scene = all.first(where: { $0.name == name }) else {
            throw FixtureError("No scene named “\(name)”. Scenes: \(names.joined(separator: ", ")).")
        }
        let home = try SceneHome()
        let editor = Editor(
            home: home.home, store: home.temporary.configStore, history: home.temporary.historyStore,
            browsers: home.browsers)
        let login: LoginStatus = name == "login-approval" ? .requiresApproval : .disabled
        let settings = SettingsModel(
            editor: editor,
            services: .shown(
                login: login, isDefault: !["not-default-browser", "default-browser-error"].contains(name),
                makeDefaultError: name == "default-browser-error"
                    ? "macOS didn’t make \(Identity.appName) open https links (The file couldn’t be opened.). Choose it in System Settings → Desktop & Dock → Default web browser."
                    : nil))
        settings.refresh()
        settings.showLogin(login)
        let picker = PickerModel(
            store: home.temporary.configStore, history: home.temporary.historyStore, browsers: home.browsers,
            services: .shown)
        picker.state.link = "https://github.com/acme/api/pull/12"
        try scene.setup(settings, picker, home)
        let view: AnyView
        let size: CGSize
        switch scene.kind {
        case .settings:
            view = AnyView(SettingsView(model: settings))
            size = SettingsView.size
        case .ruleSheet:
            view = AnyView(RuleSheet(model: settings).fixedSize())
            size = CGSize(width: 500, height: 440)
        case .picker:
            view = AnyView(PickerView(model: picker))
            size = CGSize(width: PickerModel.width, height: picker.height)
        }
        return Instance(view: view, size: size, settings: settings, picker: picker, home: home)
    }
}

extension SettingsModel {
    /// Shows a launch-at-login status without asking the system, for scenes.
    func showLogin(_ status: LoginStatus) {
        loginForScene = status
    }
}
