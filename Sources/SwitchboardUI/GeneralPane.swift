import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The default destination, the default browser, startup, history and the settings file.
struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let e = model.editor
        Form {
            Section { PaneHeader(pane: .general) }

            Section {
                BrowserPicker(
                    title: "Browser", selection: e.config.browser, browsers: e.installed, editor: e,
                    allowsDefault: false
                ) { browser in
                    model.edit { $0.selectDefaultBrowser(browser ?? "") }
                }
                .accessibilityIdentifier("default-browser")
                ProfilePicker(
                    title: "Profile", browser: e.config.browser, selection: e.config.defaultProfile, editor: e
                ) {
                    profile in model.edit { $0.selectDefaultProfile(profile) }
                }
                .accessibilityIdentifier("default-profile")
                if let error = e.profileError { ErrorText(error) }
            } header: {
                Text("Default destination")
            } footer: {
                Text("Links that match no rule open here.").foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    if model.isDefaultBrowser {
                        Label("Default", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Button("Make Default…") { model.makeDefaultBrowser() }
                    }
                } label: {
                    RowLabel(
                        title: model.isDefaultBrowser
                            ? "\(Identity.appName) opens your links" : "Another browser opens your links",
                        caption: "Links you click in other apps come here first, then go where the rules say."
                    ) {
                        SymbolTile(symbol: "safari", color: .blue)
                    }
                }
                if let error = model.defaultBrowserError {
                    ErrorText(error)
                    Button("Open System Settings") { model.services.openDefaultBrowserSettings() }
                }
            } header: {
                Text("Default web browser")
            }

            Section("Startup") {
                let on = model.login == .enabled || model.login == .requiresApproval
                Toggle(isOn: Binding(get: { on }, set: { model.setLoginEnabled($0) })) {
                    RowLabel(title: "Open at login", caption: loginDescription) {
                        SymbolTile(symbol: "power", color: .green)
                    }
                }
                .toggleStyle(.switch)
                .disabled(model.login == nil)
                if model.login == .requiresApproval {
                    LabeledContent("Login Items") {
                        Button("Open System Settings") { model.services.openLoginSettings() }
                    }
                }
                if let error = model.loginError { ErrorText(error) }
            }

            Section("History") {
                Toggle(
                    isOn: Binding(
                        get: { e.config.historyEnabled },
                        set: { on in model.edit { $0.setHistoryEnabled(on) } })
                ) {
                    RowLabel(
                        title: "Keep a history of opened links",
                        caption: "So you and your agents can ask why a link opened where it did"
                    ) {
                        SymbolTile(symbol: "clock.arrow.circlepath", color: .purple)
                    }
                }
                .toggleStyle(.switch)
                LabeledContent("Clear history") {
                    Button("Clear") { model.edit { $0.clearHistory() } }
                }
                if let error = e.historyError { ErrorText(error) }
            }

            Section {
                LabeledContent {
                    Button("Show in Finder") { model.revealConfigFile() }
                } label: {
                    RowLabel(title: "Settings file", caption: model.configPath) {
                        SymbolTile(symbol: "doc.text", color: .gray)
                    }
                }
                if e.canImportCurrentApp {
                    LabeledContent {
                        Button("Import") { model.importCurrentApp() }.prominentButton()
                    } label: {
                        RowLabel(
                            title: "Import from Switchboard",
                            caption:
                                "Copies the current app’s rules and destinations. Its own file isn’t changed."
                        ) {
                            SymbolTile(symbol: "square.and.arrow.down", color: .indigo)
                        }
                    }
                }
                if let error = model.importError { ErrorText(error) }
            } header: {
                Text("Configuration")
            } footer: {
                Text("\(Identity.cliName) reads and changes the same file.").foregroundStyle(.secondary)
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
        let shown = (selection?.isEmpty ?? true) && allowsDefault ? editor.config.browser : (selection ?? "")
        Picker(selection: Binding(get: { selection ?? "" }, set: { onSelect($0.isEmpty ? nil : $0) })) {
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
        } label: {
            RowLabel(title: title) { BrowserIcon(locator: shown, size: 22) }
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

    init(
        title: String, browser: String, selection: String, editor: Editor,
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.browser = browser
        self.selection = selection
        self.editor = editor
        self.onSelect = onSelect
    }

    var body: some View {
        let profiles = editor.profiles(of: browser)
        let resolved = (try? Profiles.directory(selection, in: profiles)) ?? selection
        Picker(selection: Binding(get: { resolved }, set: { onSelect($0) })) {
            if resolved.isEmpty {
                Text(browser.isEmpty ? "Choose a browser first" : "Choose a profile").tag("")
            }
            ForEach(profiles, id: \.directory) { profile in
                Text(
                    profile.name == profile.directory
                        ? profile.name : "\(profile.name)  (\(profile.directory))"
                )
                .tag(profile.directory)
            }
            if !resolved.isEmpty, !profiles.contains(where: { $0.directory == resolved }) {
                Text("\(selection) (unavailable)").tag(resolved)
            }
        } label: {
            RowLabel(title: title) { SymbolTile(symbol: "person.crop.circle.fill", color: .teal) }
        }
        .disabled(browser.isEmpty)
    }
}
