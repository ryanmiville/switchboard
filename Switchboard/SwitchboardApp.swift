import AppKit
import SwiftUI

@main
struct SwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "settings") {
            ContentView(viewModel: appDelegate.viewModel, onOpen: appDelegate.editorAppeared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = ConfigViewModel()
    private var session = RoutingSession()
    private var openSettingsWindow: (() -> Void)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.finishLaunching()
        if !session.keepsEditorOpen {
            NSApp.setActivationPolicy(.accessory)
            for window in NSApp.windows { window.orderOut(nil) }
        }
    }

    // SwiftUI owns creation/reopening of the settings window.
    func editorAppeared(_ openWindow: @escaping () -> Void) {
        openSettingsWindow = openWindow
        if session.isRoutingLaunch {
            for window in NSApp.windows { window.orderOut(nil) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showEditor()
        return true
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
            if session.keepsEditorOpen {
                guard viewModel.flush() else {
                    showRoutingError(
                        viewModel.loadError ?? viewModel.saveError ?? "Your settings couldn’t be saved.",
                        url: url)
                    scheduleTermination(after: ticket)
                    return
                }
                config = viewModel.config
            } else {
                config = try Config.loadOrDefault()
            }
            try BrowserLauncher(config: config).launch(
                url: url, profileName: Router(config: config).route(url: url))
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
        NSApp.setActivationPolicy(.regular)
        openSettingsWindow?()
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard session.keepsEditorOpen, viewModel.hasUnsavedChanges, !viewModel.flush() else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Your changes haven’t been saved"
        alert.informativeText =
            viewModel.saveError ?? "Keep editing to fix the issue, or quit and discard these changes."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
