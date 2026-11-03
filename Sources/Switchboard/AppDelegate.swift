import AppKit
import SwiftUI
import SwitchboardCore
import SwitchboardEditor
import SwitchboardMac
import SwitchboardUI

/// Wires the app together: link delivery and the app's lifetime, the menu-bar item, the settings
/// window, the Quick Switch panel and shortcut, and following config.json.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var home: Home!
    private var settings: SettingsModel!
    private var picker: QuickSwitchPanel!
    private var session = RoutingSession()
    private var menuBar: MenuBar?
    private var window: NSWindow?
    private let shortcut = GlobalShortcut()
    private var watcher: FileWatcher?
    private var startupError: String?

    static func now() -> Timestamp { Timestamp(Date()) }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Links arrive as GetURL Apple Events. Reading the event's string, not a URL, keeps the link
        // exactly as it was sent. Registered before launch finishes, so the launching link arrives.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

        let (home, env) = Env.fromProcess()
        // Without $HOME there is nowhere to read settings from; an empty folder lets the app say so.
        self.home = home ?? Home(path: "/var/empty")
        if home == nil { startupError = "$HOME isn’t set, so \(Identity.appName) can’t find its settings." }
        let browsers = Browsers(home: self.home, env: env)
        let editor = Editor(
            home: self.home, store: ConfigStore(url: self.home.configFile),
            history: HistoryStore(url: self.home.historyFile), browsers: browsers)
        let loginItem = LoginItem()
        settings = SettingsModel(
            editor: editor,
            services: SettingsServices(
                loginStatus: { loginItem.status() }, setLoginEnabled: { try loginItem.setEnabled($0) },
                openLoginSettings: { loginItem.openSettings() },
                registerShortcut: { [weak self] chord in self?.register(chord) },
                isDefaultBrowser: { DefaultBrowser.isDefault },
                makeDefaultBrowser: { done in DefaultBrowser.makeDefault(done: done) },
                openQuickSwitch: { [weak self] in self?.picker.summon() },
                openDefaultBrowserSettings: { DefaultBrowser.openSettings() }))
        picker = QuickSwitchPanel(
            store: ConfigStore(url: self.home.configFile), history: HistoryStore(url: self.home.historyFile),
            browsers: browsers, settings: settings, openSettings: { [weak self] in self?.showSettings() })
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin =
            event?.eventClass == kCoreEventClass && event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        session.finishLaunching(atLogin: atLogin)
        if session.isResident { startResident() }
        if let startupError {
            settings.failure = Failure(url: "", reason: startupError)
            showSettings()
        }
    }

    /// The menu-bar item, the shortcut and the file watcher: what a running app needs.
    private func startResident() {
        guard menuBar == nil else { return }
        menuBar = MenuBar { [weak self] action in
            switch action {
            case .quickSwitch: self?.picker.summon()
            case .openSettings: self?.showSettings()
            case .quit: NSApp.terminate(nil)
            }
        }
        shortcut.onPress = { [weak self] in self?.picker.summon() }
        if let chord = KeyChord(settings.shortcut) {
            if let error = register(chord) { settings.shortcutRefused(error) }
        } else {
            settings.shortcutRefused(
                "The saved shortcut “\(settings.shortcut.text)” isn’t one macOS can register.")
        }
        watcher = FileWatcher(home.configFile) { [weak self] in
            Task { @MainActor in
                self?.settings.edit { $0.checkExternal() }
                self?.picker.refresh()
            }
        }
    }

    /// Registers the Quick Switch shortcut. Returns why it was refused.
    private func register(_ chord: KeyChord) -> String? {
        do {
            try shortcut.register(chord)
            menuBar?.setShortcutHint(chord.display)
            return nil
        } catch {
            return error.description
        }
    }

    // MARK: Links

    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard let link = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        receive(link)
    }

    /// Local HTML files, from the document types in Info.plist. Web links arrive through
    /// `handleGetURL`, which keeps their exact string.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL { receive(url.absoluteString) }
    }

    private func receive(_ link: String) {
        let ticket = session.receiveLink()
        var failure: String?
        settings.edit { editor in failure = Routing.receive(link, editor: &editor, now: Self.now()) }
        if let failure {
            // A failure stays on screen with recovery actions instead of opening somewhere else.
            session.stayResident()
            startResident()
            settings.failure = Failure(url: link, reason: failure)
            showSettings()
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Routing.idleExit))
            guard let self, self.session.shouldQuit(after: ticket) else { return }
            NSApp.terminate(nil)
        }
    }

    // MARK: Settings window

    func showSettings() {
        session.stayResident()
        startResident()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: SettingsView.size),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = Identity.appName
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: settings))
            window.center()
            self.window = window
        }
        settings.refresh()
        bringToFront()
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        settings.flush()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        settings.refresh()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again (Finder, Spotlight) means the person wants Settings.
        showSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        settings.flush()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        shortcut.stop()
    }
}
