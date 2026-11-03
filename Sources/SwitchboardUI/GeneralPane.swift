import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The default destination, the default browser, startup, history and the settings file.
struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let e = model.editor
        Form {
            Section {
                BrowserPicker(
                    title: "Browser", selection: e.config.browser, browsers: e.installed, editor: e,
                    allowsDefault: false
                ) { browser in
                    model.edit { $0.selectDefaultBrowser(browser ?? "") }
                }
                .accessibilityIdentifier("default-browser")
                ProfilePicker(title: "Profile", browser: e.config.browser, selection: e.config.defaultProfile, editor: e) {
                    profile in model.edit { $0.selectDefaultProfile(profile) }
                }
                .accessibilityIdentifier("default-profile")
                if let error = e.profileError { ErrorText(error) }
            } header: {
                Text("Default destination")
            } footer: {
                Text("Links that match no rule open here.").foregroundStyle(.secondary)
            }

            Section("Default browser") {
                LabeledContent(model.isDefaultBrowser ? "\(Identity.appName) opens your links" : "Another browser opens your links") {
                    if !model.isDefaultBrowser {
                        Button("Make Default…") { model.makeDefaultBrowser() }
                    }
                }
                if let error = model.defaultBrowserError { ErrorText(error) }
            }

            Section("Startup") {
                let on = model.login == .enabled || model.login == .requiresApproval
                Toggle(isOn: Binding(get: { on }, set: { model.setLoginEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open at login")
                        Text(loginDescription).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(model.login == nil)
                if model.login == .requiresApproval {
                    LabeledContent("Login Items") {
                        Button("Open System Settings") { model.services.openLoginSettings() }
                    }
                }
                if let error = model.loginError { ErrorText(error) }
            }

            Section("History") {
                Toggle(isOn: Binding(get: { e.config.historyEnabled }, set: { on in model.edit { $0.setHistoryEnabled(on) } }))
                {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep a history of opened links")
                        Text("So you and your agents can ask why a link opened where it did")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Clear history") {
                    Button("Clear") { model.edit { $0.clearHistory() } }
                }
                if let error = e.historyError { ErrorText(error) }
            }

            Section("Configuration") {
                LabeledContent("Settings file") {
                    HStack {
                        Text(model.configPath).font(.callout.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Reveal") { model.revealConfigFile() }
                    }
                }
                Text("\(Identity.cliName) reads and changes the same file.").font(.caption).foregroundStyle(.secondary)
                if e.canImportCurrentApp {
                    LabeledContent("Switchboard’s settings") {
                        Button("Import") { model.importCurrentApp() }
                    }
                    Text("Copies the rules and destinations from the current Switchboard app. Its own file isn’t changed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.importError { ErrorText(error) }
            }
        }
        .formStyle(.grouped)
    }

    private var loginDescription: String {
        switch model.login {
        case .requiresApproval: "Waiting for you to allow it in System Settings → Login Items"
        case nil: "Checking…"
        default: "Keeps the menu-bar item and Quick Switch ready"
        }
    }
}

/// A menu of installed browsers, by name, with an optional "Default browser" choice.
struct BrowserPicker: View {
    let title: String
    let selection: String?
    let browsers: [BrowserInfo]
    let editor: Editor
    let allowsDefault: Bool
    let onSelect: (String?) -> Void

    init(
        title: String, selection: String?, browsers: [BrowserInfo], editor: Editor, allowsDefault: Bool,
        onSelect: @escaping (String?) -> Void
    ) {
        self.title = title
        self.selection = selection
        self.browsers = browsers
        self.editor = editor
        self.allowsDefault = allowsDefault
        self.onSelect = onSelect
    }

    var body: some View {
        Picker(title, selection: Binding(get: { selection ?? "" }, set: { onSelect($0.isEmpty ? nil : $0) })) {
            if allowsDefault {
                Text("Default browser (\(editor.browserName(editor.config.browser)))").tag("")
            } else if selection?.isEmpty ?? true {
                Text("Choose a browser").tag("")
            }
            ForEach(browsers, id: \.locator) { browser in
                Text(browser.name).tag(browser.locator)
            }
            // A saved browser that isn't installed stays visible instead of silently changing.
            if let selection, !selection.isEmpty, !browsers.contains(where: { $0.locator == selection }) {
                Text("\(Browsers.fileStem(selection)) (unavailable)").tag(selection)
            }
        }
    }
}

/// A menu of one browser's profiles, saved as directory identifiers.
struct ProfilePicker: View {
    let title: String
    let browser: String
    let selection: String
    let editor: Editor
    let onSelect: (String) -> Void

    init(title: String, browser: String, selection: String, editor: Editor, onSelect: @escaping (String) -> Void) {
        self.title = title
        self.browser = browser
        self.selection = selection
        self.editor = editor
        self.onSelect = onSelect
    }

    var body: some View {
        let profiles = editor.profiles(of: browser)
        let resolved = (try? Profiles.directory(selection, in: profiles)) ?? selection
        Picker(title, selection: Binding(get: { resolved }, set: { onSelect($0) })) {
            if resolved.isEmpty {
                Text(browser.isEmpty ? "Choose a browser first" : "Choose a profile").tag("")
            }
            ForEach(profiles, id: \.directory) { profile in
                Text(profile.name == profile.directory ? profile.name : "\(profile.name)  (\(profile.directory))")
                    .tag(profile.directory)
            }
            if !resolved.isEmpty, !profiles.contains(where: { $0.directory == resolved }) {
                Text("\(selection) (unavailable)").tag(resolved)
            }
        }
        .disabled(browser.isEmpty)
    }
}
