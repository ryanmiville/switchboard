import SwiftUI
import AppKit

@main
struct SwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchedViaURL = false
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register URL handler before app finishes launching
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // If launched via URL, become accessory (no dock/menu) and quit after routing
        // If launched directly, show the config window
        if launchedViaURL {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        launchedViaURL = true
        
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        
        routeURL(url)
    }
    
    // Fallback for URLs opened via NSApplicationDelegate
    func application(_ application: NSApplication, open urls: [URL]) {
        launchedViaURL = true
        for url in urls {
            routeURL(url)
        }
    }
    
    private func routeURL(_ url: URL) {
        // Hide dock icon when routing
        NSApp.setActivationPolicy(.accessory)
        
        do {
            let config = try Config.load()
            let router = Router(config: config)
            let profile = router.route(url: url)
            let launcher = BrowserLauncher(config: config)
            launcher.launch(url: url, profile: profile)
        } catch {
            // Fallback: just open in default browser app directly
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Helium", url.absoluteString]
            try? process.run()
        }
        
        // Quit after routing - we don't need to stay open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}
