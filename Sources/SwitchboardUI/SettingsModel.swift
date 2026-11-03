import AppKit
import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// What the settings window needs from the system, passed in by the app. Scenes and tests pass
/// `SettingsServices.shown`, which only changes what the window shows.
public struct SettingsServices {
    /// Reads launch at login. Can block; called off the main thread.
    public var loginStatus: @Sendable () -> LoginStatus
    /// Turns launch at login on or off and returns the status afterwards. Can block.
    public var setLoginEnabled: @Sendable (Bool) throws -> LoginStatus
    public var openLoginSettings: @MainActor () -> Void
    /// Registers the Quick Switch shortcut; returns why it was refused.
    public var registerShortcut: @MainActor (KeyChord) -> String?
    public var isDefaultBrowser: @MainActor () -> Bool
    public var makeDefaultBrowser: @MainActor (@escaping @MainActor @Sendable (String?) -> Void) -> Void
    /// Opens System Settings → Desktop & Dock, where the default browser is chosen by hand.
    public var openDefaultBrowserSettings: @MainActor () -> Void
    /// Shows the Quick Switch panel.
    public var openQuickSwitch: @MainActor () -> Void

    public init(
        loginStatus: @escaping @Sendable () -> LoginStatus,
        setLoginEnabled: @escaping @Sendable (Bool) throws -> LoginStatus,
        openLoginSettings: @escaping @MainActor () -> Void,
        registerShortcut: @escaping @MainActor (KeyChord) -> String?,
        isDefaultBrowser: @escaping @MainActor () -> Bool,
        makeDefaultBrowser: @escaping @MainActor (@escaping @MainActor @Sendable (String?) -> Void) -> Void,
        openQuickSwitch: @escaping @MainActor () -> Void,
        openDefaultBrowserSettings: @escaping @MainActor () -> Void = {}
    ) {
        self.openDefaultBrowserSettings = openDefaultBrowserSettings
        self.loginStatus = loginStatus
        self.setLoginEnabled = setLoginEnabled
        self.openLoginSettings = openLoginSettings
        self.registerShortcut = registerShortcut
        self.isDefaultBrowser = isDefaultBrowser
        self.makeDefaultBrowser = makeDefaultBrowser
        self.openQuickSwitch = openQuickSwitch
    }

    /// No system calls: launch at login is shown as `login`, this is the default browser when
    /// `isDefault`, and asking to make it the default fails with `makeDefaultError` when given.
    public static func shown(
        login: LoginStatus = .disabled, isDefault: Bool = true, makeDefaultError: String? = nil
    ) -> SettingsServices {
        SettingsServices(
            loginStatus: { login }, setLoginEnabled: { $0 ? .enabled : .disabled }, openLoginSettings: {},
            registerShortcut: { _ in nil }, isDefaultBrowser: { isDefault },
            makeDefaultBrowser: { $0(makeDefaultError) }, openQuickSwitch: {})
    }
}

public enum Pane: String, CaseIterable, Identifiable, Sendable {
    case general, routing, quickSwitch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .routing: "Routing"
        case .quickSwitch: "Quick Switch"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .routing: "arrow.triangle.branch"
        case .quickSwitch: "bolt"
        }
    }
}

/// A link the app couldn't open, shown with recovery actions.
public struct Failure: Equatable, Sendable {
    public var url: String
    public var reason: String

    public init(url: String, reason: String) {
        self.url = url
        self.reason = reason
    }
}

/// The settings window's state: the editor and everything the window shows around it.
@MainActor
public final class SettingsModel: ObservableObject {
    @Published public var editor: Editor
    @Published public var pane: Pane = .general
    @Published public var failure: Failure?
    @Published public var selected: RuleID?
    @Published public var draft: Draft?
    @Published public var testURL = ""
    /// `nil` until the first answer arrives.
    @Published public private(set) var login: LoginStatus?
    /// Set by scenes, so a render shows a status without waiting for an answer.
    var loginForScene: LoginStatus? {
        get { login }
        set { login = newValue }
    }
    @Published public private(set) var loginError: String?
    @Published public private(set) var isDefaultBrowser = true
    @Published public private(set) var defaultBrowserError: String?
    @Published public private(set) var shortcutError: String?
    @Published public var importError: String?

    public let services: SettingsServices
    private var autosave: Task<Void, Never>?

    public init(editor: Editor, services: SettingsServices) {
        self.editor = editor
        self.services = services
    }

    /// Re-reads what the system may have changed: the file, launch at login, the default browser.
    /// Called when the window comes forward.
    public func refresh() {
        editor.checkExternal()
        isDefaultBrowser = services.isDefaultBrowser()
        let read = services.loginStatus
        Task {
            let status = await Task.detached { read() }.value
            login = status
        }
    }

    /// Runs `change` on the editor and saves it after the autosave delay.
    public func edit(_ change: (inout Editor) -> Void) {
        change(&editor)
        scheduleSave()
    }

    private func scheduleSave() {
        autosave?.cancel()
        guard editor.hasUnsavedChanges else { return }
        autosave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Editor.autosaveDelay))
            guard !Task.isCancelled else { return }
            self?.editor.flush()
        }
    }

    /// Saves pending edits now. Returns whether everything is saved.
    @discardableResult
    public func flush() -> Bool {
        autosave?.cancel()
        return editor.flush()
    }

    // MARK: Launch at login and the default browser

    public func setLoginEnabled(_ enabled: Bool) {
        loginError = nil
        let set = services.setLoginEnabled
        Task {
            let result = await Task.detached { Result { try set(enabled) } }.value
            switch result {
            case .success(let status): login = status
            case .failure(let error):
                loginError = "Open at login couldn’t be changed. \(error.localizedDescription)"
            }
        }
    }

    public func makeDefaultBrowser() {
        defaultBrowserError = nil
        services.makeDefaultBrowser { [weak self] error in
            self?.defaultBrowserError = error
            self?.isDefaultBrowser = self?.services.isDefaultBrowser() ?? false
        }
    }

    // MARK: Quick Switch

    public var shortcut: Shortcut { editor.config.picker?.shortcut ?? .standard }

    /// A newly recorded shortcut: registered first, so a chord the system refuses is never saved.
    public func record(_ chord: KeyChord) {
        guard let text = chord.shortcut else {
            shortcutError = "That key can’t be used for a shortcut."
            return
        }
        if let error = services.registerShortcut(chord) {
            shortcutError = error
            return
        }
        shortcutError = nil
        var settings = editor.config.picker ?? PickerSettings()
        settings.shortcut = text
        edit { $0.setPicker(settings) }
    }

    /// Marks the saved shortcut as not registered, when the system refused it at launch.
    public func shortcutRefused(_ error: String) {
        shortcutError = error
    }

    /// Shows or hides a destination in the Quick Switch panel. The first change lists every
    /// destination explicitly, so newly installed browsers stay hidden until chosen.
    public func setShown(_ destination: Destination, _ shown: Bool, all: [Destination]) {
        var settings = editor.config.picker ?? PickerSettings()
        var list = settings.destinations ?? all
        list.removeAll { $0 == destination }
        if shown { list.append(destination) }
        settings.destinations = all.filter { list.contains($0) }
        edit { $0.setPicker(settings) }
    }

    public func toggleFavorite(_ choice: Choice) {
        var settings = editor.config.picker ?? PickerSettings()
        if settings.favorites.contains(where: { $0.destination == choice.destination }) {
            settings.favorites.removeAll { $0.destination == choice.destination }
        } else {
            settings.favorites.append(
                Favorite(
                    browser: choice.destination.browser, profile: choice.destination.profile,
                    name: choice.profileName))
        }
        edit { $0.setPicker(settings) }
    }

    // MARK: Rules

    public var selectedIndex: Int? { selected.flatMap { editor.config.index(of: $0) } }

    public func editSelected() {
        guard let i = selectedIndex else { return }
        draft = .editing(editor.config.rules[i])
    }

    public func deleteSelected() {
        guard let i = selectedIndex else { return }
        let id = editor.config.rules[i].id
        edit { $0.deleteRule(id) }
        let rules = editor.config.rules
        selected = rules.isEmpty ? nil : rules[min(i, rules.count - 1)].id
    }

    /// Validates the draft and saves it into the config, or shows why not.
    public func commitDraft() {
        guard var draft else { return }
        guard let rule = draft.validated() else {
            self.draft = draft
            return
        }
        var committed = false
        edit { committed = $0.commitRule(rule) }
        if committed {
            selected = rule.id
            self.draft = nil
        }
    }

    // MARK: Notices

    public func copyFailedLink() {
        guard let failure else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(failure.url, forType: .string)
        self.failure = nil
    }

    public func importCurrentApp() {
        importError = editor.importCurrentApp()
    }

    public func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([editor.store.url])
    }
}
