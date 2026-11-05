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
    /// The current time, for how long ago a recent link opened.
    public var now: @MainActor () -> Timestamp

    public init(
        loginStatus: @escaping @Sendable () -> LoginStatus,
        setLoginEnabled: @escaping @Sendable (Bool) throws -> LoginStatus,
        openLoginSettings: @escaping @MainActor () -> Void,
        registerShortcut: @escaping @MainActor (KeyChord) -> String?,
        isDefaultBrowser: @escaping @MainActor () -> Bool,
        makeDefaultBrowser: @escaping @MainActor (@escaping @MainActor @Sendable (String?) -> Void) -> Void,
        openQuickSwitch: @escaping @MainActor () -> Void,
        now: @escaping @MainActor () -> Timestamp,
        openDefaultBrowserSettings: @escaping @MainActor () -> Void = {}
    ) {
        self.now = now
        self.openDefaultBrowserSettings = openDefaultBrowserSettings
        self.loginStatus = loginStatus
        self.setLoginEnabled = setLoginEnabled
        self.openLoginSettings = openLoginSettings
        self.registerShortcut = registerShortcut
        self.isDefaultBrowser = isDefaultBrowser
        self.makeDefaultBrowser = makeDefaultBrowser
        self.openQuickSwitch = openQuickSwitch
    }

    /// The time scenes and tests are shown at: 2025-10-29T17:04:11Z.
    public static let sceneTime = Timestamp(1_761_757_451)

    /// No system calls: launch at login is shown as `login`, this is the default browser when
    /// `isDefault`, asking to make it the default fails with `makeDefaultError` when given, and the
    /// time is always `sceneTime`.
    public static func shown(
        login: LoginStatus = .disabled, isDefault: Bool = true, makeDefaultError: String? = nil
    ) -> SettingsServices {
        SettingsServices(
            loginStatus: { login }, setLoginEnabled: { $0 ? .enabled : .disabled }, openLoginSettings: {},
            registerShortcut: { _ in nil }, isDefaultBrowser: { isDefault },
            makeDefaultBrowser: { $0(makeDefaultError) }, openQuickSwitch: {}, now: { Self.sceneTime })
    }
}

public enum Pane: String, CaseIterable, Identifiable, Sendable {
    case general, routing, recent, quickSwitch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .routing: "Routing"
        case .recent: "Recent Links"
        case .quickSwitch: "Quick Switch"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .routing: "arrow.triangle.branch"
        case .recent: "clock.arrow.circlepath"
        case .quickSwitch: "bolt"
        }
    }
}

/// A link the app couldn't open, shown with recovery actions.
public struct Failure: Equatable, Sendable {
    public var url: String
    public var reason: String
    /// The rule that sent the link where it failed, if one matched.
    public var rule: RuleID?

    public init(url: String, reason: String, rule: RuleID? = nil) {
        self.url = url
        self.reason = reason
        self.rule = rule
    }
}

/// The settings window's state: the editor and everything the window shows around it.
@MainActor
public final class SettingsModel: ObservableObject {
    @Published public var editor: Editor
    /// The pane on show. Every change is remembered for the toolbar's back and forward buttons.
    @Published public var pane: Pane = .general {
        didSet {
            guard pane != oldValue, !navigating else { return }
            backPanes.append(oldValue)
            forwardPanes.removeAll()
        }
    }
    /// The panes shown before this one, the most recent last.
    @Published public private(set) var backPanes: [Pane] = []
    /// The panes left by going back, the most recent last.
    @Published public private(set) var forwardPanes: [Pane] = []
    private var navigating = false
    @Published public var failure: Failure?
    @Published public var selected: RuleID?
    @Published public var draft: Draft? {
        didSet {
            if let draft, draft.id != oldValue?.id { recentLinks = editor.recentLinks() }
        }
    }
    /// Links from history, newest first, read when a rule sheet opens for its preview.
    @Published public private(set) var recentLinks: [String] = []
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
    /// When the window last looked at the clock, for how long ago recent links opened.
    @Published public private(set) var now: Timestamp

    public let services: SettingsServices
    private var autosave: Task<Void, Never>?

    /// Returns to the pane shown before this one.
    public func goBack() {
        guard let previous = backPanes.popLast() else { return }
        forwardPanes.append(pane)
        show(previous)
    }

    /// Returns to the pane left by going back.
    public func goForward() {
        guard let next = forwardPanes.popLast() else { return }
        backPanes.append(pane)
        show(next)
    }

    private func show(_ pane: Pane) {
        navigating = true
        self.pane = pane
        navigating = false
    }

    public init(editor: Editor, services: SettingsServices) {
        self.editor = editor
        self.services = services
        now = services.now()
    }

    /// Re-reads what the system may have changed: the file, launch at login, the default browser.
    /// Called when the window comes forward.
    public func refresh() {
        editor.checkExternal()
        reloadRecent()
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

    /// Moves a rule that never matches above the rule that hides it, and selects it.
    public func moveAbove(_ id: RuleID, to index: Int) {
        edit { $0.moveRule(id, to: index) }
        selected = id
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

    // MARK: Recent links

    /// Reads history again, when the window comes forward or another process recorded a link.
    public func reloadRecent() {
        editor.loadRecent()
        now = services.now()
    }

    /// Opens the rule sheet for a new rule that matches `entry`'s link.
    public func addRule(for entry: History.Entry) {
        draft = .forLink(entry, defaultBrowser: editor.config.browser)
    }

    public func copyLink(_ link: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    // MARK: Notices

    public func copyFailedLink() {
        guard let failure else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(failure.url, forType: .string)
        self.failure = nil
    }

    /// The rule behind the failed link, while it is still in the settings.
    public var failedRuleIndex: Int? { failure?.rule.flatMap { editor.config.index(of: $0) } }

    /// Opens the rule sheet for the rule behind the failed link, on the Routing pane. The notice
    /// stays until it is dismissed, so the link can still be copied.
    public func fixFailedRule() {
        guard let i = failedRuleIndex else { return }
        let rule = editor.config.rules[i]
        pane = .routing
        selected = rule.id
        draft = .editing(rule)
    }

    public func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([editor.store.url])
    }
}
