import AppKit
import SwiftUI

#if !SWIFT_PACKAGE
    @main
    struct SwitchboardApp: App {
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

        var body: some Scene {
            Window("Switchboard", id: "settings") {
                ContentView(
                    viewModel: appDelegate.viewModel, picker: appDelegate.picker,
                    loginItem: appDelegate.loginItem,
                    onOpen: appDelegate.editorAppeared)
            }
            .defaultSize(width: 880, height: 700)
            .windowResizability(.contentMinSize)
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.openSettingsFromMenu() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
        }
    }
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let viewModel: ConfigViewModel
    private(set) lazy var picker = TabPickerController(viewModel: viewModel)
    private(set) lazy var loginItem = LoginItemController()
    private var session = RoutingSession()
    private var openSettingsWindow: (() -> Void)?
    private let enableResidentTools: Bool
    private var statusItem: NSStatusItem?
    var launchEvent: () -> NSAppleEventDescriptor? = { NSAppleEventManager.shared().currentAppleEvent }

    override convenience init() {
        self.init(viewModel: ConfigViewModel())
    }

    init(viewModel: ConfigViewModel, enableResidentTools: Bool = true) {
        self.viewModel = viewModel
        self.enableResidentTools = enableResidentTools
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.finishLaunching(atLogin: Self.wasLaunchedAtLogin(launchEvent()))
        NSApp.setActivationPolicy(.accessory)
        if !session.keepsEditorOpen {
            for window in NSApp.windows { window.orderOut(nil) }
        }
        if session.keepsRunning { startResidentTools() }
    }

    static func wasLaunchedAtLogin(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.eventClass == kCoreEventClass && event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    // SwiftUI owns creation/reopening of the settings window.
    func editorAppeared(_ openWindow: @escaping () -> Void) {
        openSettingsWindow = openWindow
        if session.hidesEditor {
            for window in NSApp.windows { window.orderOut(nil) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        session.startResident()
        startResidentTools()
        // Opening the app only starts its menu bar; Settings requires an explicit menu action.
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the menu bar and global shortcut alive; link-only launches use their idle timer.
        false
    }

    @objc func handleGetURL(
        _ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: value)
        else { return }
        routeURL(url)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { routeURL(url) }
    }

    private func routeURL(_ url: URL) {
        let ticket = session.receiveURL()
        if !session.keepsEditorOpen { NSApp.setActivationPolicy(.accessory) }
        do {
            let config: Config
            if session.keepsRunning {
                guard viewModel.flush() else {
                    showRoutingError(
                        viewModel.loadError ?? viewModel.saveError ?? viewModel.profileError
                            ?? "Your settings couldn’t be saved.",
                        url: url)
                    scheduleTermination(after: ticket)
                    return
                }
                config = viewModel.config
            } else {
                config = try Config.loadOrDefault()
            }
            try BrowserLauncher().launch(url: url, destination: Router(config: config).route(url: url))
        } catch {
            showRoutingError(error.localizedDescription, url: url)
        }
        scheduleTermination(after: ticket)
    }

    private func scheduleTermination(after ticket: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.session.shouldTerminate(after: ticket) else { return }
            NSApp.terminate(nil)
        }
    }

    private func showRoutingError(_ reason: String, url: URL) {
        let alert = NSAlert()
        alert.messageText = "The link couldn’t be opened"
        alert.informativeText =
            "\(reason) Open Switchboard’s settings to fix the issue, or copy the link to open it yourself."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Copy Link")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            showEditor()
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }

    private func showEditor() {
        session.openEditor()
        startResidentTools()
        NSApp.setActivationPolicy(.accessory)
        if let window = NSApp.windows.first(where: {
            $0.isMiniaturized || ($0.canBecomeMain && $0.isVisible)
        }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openSettingsWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startResidentTools() {
        guard enableResidentTools, statusItem == nil else { return }
        picker.onSettings = { [weak self] in
            UserDefaults.standard.set("quickSwitch", forKey: "settingsPane")
            self?.showEditor()
        }
        picker.start()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(named: "MenuBarIcon")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = "Switchboard"
        item.button?.image = image
        item.button?.toolTip = "Switchboard — open the current page in another profile"
        let menu = NSMenu()
        menu.delegate = self
        for (title, action) in [
            ("Open Current Page…", #selector(showTabPicker)),
            ("Settings…", #selector(openSettingsFromMenu)),
            ("Quit Switchboard", #selector(quitFromMenu)),
        ] {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menu.addItem(menuItem)
        }
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let shortcut = viewModel.config.picker?.shortcut ?? .default
        menu.items.first?.title = "Open Current Page…  \(shortcut.label)"
    }

    @objc private func showTabPicker() { picker.show() }
    @objc func openSettingsFromMenu() { showEditor() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard session.keepsRunning, viewModel.hasUnsavedChanges, !viewModel.flush() else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Your changes haven’t been saved"
        alert.informativeText =
            viewModel.saveError ?? viewModel.profileError
            ?? "Keep editing to fix the issue, or quit and discard these changes."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
