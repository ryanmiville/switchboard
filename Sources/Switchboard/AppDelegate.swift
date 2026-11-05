import AppKit
import SwiftUI
import SwitchboardCore
import SwitchboardEditor
import SwitchboardMac
import SwitchboardUI

/// What the menu-bar item shows. The `App` observes it directly: SwiftUI's delegate adaptor
/// gives no binding to the delegate's own properties.
@MainActor
final class MenuBarState: ObservableObject {
    static let shared = MenuBarState()
    /// Whether the item is shown: only while the app is resident, never for a launch that only
    /// delivers links. Only a change publishes: `MenuBarExtra` writes the binding back each time it
    /// sees the item's visibility, and publishing that write re-evaluates the App's body, which
    /// makes it write again, forever.
    var shown = false {
        willSet { if newValue != shown { objectWillChange.send() } }
    }
    /// The registered shortcut, shown next to Quick Switch in the menu.
    @Published var shortcutHint: String?
}

/// The AppKit side of the app: link delivery and the app's lifetime, the Quick Switch panel and
/// shortcut, and following config.json. SwiftUI owns the settings window and the menu-bar item
/// (`SwitchboardApp`); this asks it to show them.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let menuBar = MenuBarState.shared
    let settings: SettingsModel
    let opener = WindowOpener()
    private let home: Home
    private var picker: QuickSwitchPanel!
    private var session = RoutingSession()
    private let shortcut = GlobalShortcut()
    private var watcher: FileWatcher?
    private var historyWatcher: FileWatcher?
    private var startupError: String?
    private var resident = false
    /// Settings was asked for, so the window stays when it appears.
    private var settingsWanted = false

    static func now() -> Timestamp { Timestamp(Date()) }

    /// `--describe-window`: open Settings, print `WindowReport`, quit.
    static var describesWindow = false
    /// `--shoot`: show a fixture scene's settings in the real window, capture it from the screen, quit.
    static var shot: WindowShot?

    override init() {
        let (home, env) = Env.fromProcess()
        // Without $HOME there is nowhere to read settings from; an empty folder lets the app say so.
        self.home = home ?? Home(path: "/var/empty")
        if home == nil { startupError = "$HOME isn’t set, so \(Identity.appName) can’t find its settings." }
        let browsers = Browsers(home: self.home, env: env)
        let editor = Editor(
            home: self.home, store: ConfigStore(url: self.home.configFile),
            history: HistoryStore(url: self.home.historyFile), browsers: browsers)
        let loginItem = LoginItem()
        let holder = Holder()
        settings = Self.shot?.scene.settings ?? SettingsModel(
            editor: editor,
            services: SettingsServices(
                loginStatus: { loginItem.status() }, setLoginEnabled: { try loginItem.setEnabled($0) },
                openLoginSettings: { loginItem.openSettings() },
                registerShortcut: { chord in holder.delegate?.register(chord) },
                isDefaultBrowser: { DefaultBrowser.isDefault },
                makeDefaultBrowser: { done in DefaultBrowser.makeDefault(done: done) },
                openQuickSwitch: { holder.delegate?.summonPicker() },
                now: { AppDelegate.now() },
                openDefaultBrowserSettings: { DefaultBrowser.openSettings() }))
        super.init()
        holder.delegate = self
        picker = QuickSwitchPanel(
            store: ConfigStore(url: self.home.configFile), history: HistoryStore(url: self.home.historyFile),
            browsers: browsers, settings: settings, openSettings: { [weak self] in self?.showSettings() })
    }

    /// Lets the settings services reach the delegate, which doesn't exist yet when they are made.
    @MainActor
    private final class Holder {
        weak var delegate: AppDelegate?
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Links arrive as GetURL Apple Events. Reading the event's string, not a URL, keeps the link
        // exactly as it was sent. Registered before launch finishes, so the launching link arrives.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin =
            event?.eventClass == kCoreEventClass && event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        session.finishLaunching(atLogin: atLogin)
        // SwiftUI has already made the settings window by now; it goes before it is drawn, as on
        // `main`, so a launch that doesn't ask for Settings never flashes it.
        if !settingsWanted { hideSettingsWindows() }
        if session.isResident { startResident() }
        if let startupError {
            settings.failure = Failure(url: "", reason: startupError)
            showSettings()
        }
        if let shot = Self.shot {
            showSettings()
            Task { @MainActor in await shot.take() }
        }
        if Self.describesWindow {
            showSettings()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                print(WindowReport.describe())
                exit(0)
            }
        }
    }

    /// The menu-bar item, the shortcut and the file watcher: what a running app needs.
    private func startResident() {
        guard !resident else { return }
        resident = true
        menuBar.shown = true
        shortcut.onPress = { [weak self] in self?.picker.toggle() }
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
        // Quick Switch records links too, and another copy of the app may route them.
        historyWatcher = FileWatcher(home.historyFile) { [weak self] in
            Task { @MainActor in self?.settings.reloadRecent() }
        }
    }

    /// Registers the Quick Switch shortcut. Returns why it was refused.
    func register(_ chord: KeyChord) -> String? {
        do {
            try shortcut.register(chord)
            menuBar.shortcutHint = chord.display
            return nil
        } catch {
            return error.description
        }
    }

    func summonPicker() { picker.summon() }

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
        var failure: LinkFailure?
        settings.edit { editor in failure = Routing.receive(link, editor: &editor, now: Self.now()) }
        if let failure {
            // A failure stays on screen with recovery actions instead of opening somewhere else.
            session.stayResident()
            startResident()
            settings.failure = Failure(url: link, reason: failure.reason, rule: failure.rule)
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
        settingsWanted = true
        settings.refresh()
        // In the Dock and the app switcher while Settings is open, like any app with a window.
        NSApp.setActivationPolicy(.regular)
        bringToFront()
        opener.openSettings()
    }

    /// Settings closed: back to a menu-bar app, out of the Dock.
    func settingsWindowClosed() {
        settings.flush()
        NSApp.setActivationPolicy(.accessory)
    }

    /// SwiftUI opens the settings window at launch on its own. Unless Settings was asked for, it
    /// is ordered out at once, before it is drawn: opening the app starts its menu-bar item
    /// without opening Settings.
    func settingsWindowAppeared() {
        if !settingsWanted { hideSettingsWindows() }
    }

    /// Orders out the settings window without closing it, so its content stays and the next
    /// `openWindow` brings the same window back. The menu-bar item's and Quick Switch's windows
    /// can't become main, so they stay.
    private func hideSettingsWindows() {
        for window in NSApp.windows
        where window.identifier?.rawValue.hasPrefix(SettingsWindow.id) == true || window.canBecomeMain {
            window.orderOut(nil)
        }
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
        historyWatcher?.stop()
        shortcut.stop()
    }
}
