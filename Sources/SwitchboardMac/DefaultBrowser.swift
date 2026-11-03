import AppKit
import SwitchboardCore

/// Whether this app is the system's default browser, and asking macOS to make it so. macOS shows
/// its own confirmation; the person can also choose in System Settings → Desktop & Dock.
public enum DefaultBrowser {
    @MainActor
    public static var isDefault: Bool {
        guard let probe = URL(string: "https://example.com"),
            let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Identity.bundleID
    }

    /// Asks macOS to open http and https links with this app. `done` gets why it failed, if it did.
    @MainActor
    public static func makeDefault(done: @escaping @MainActor @Sendable (String?) -> Void) {
        guard Bundle.main.bundleIdentifier == Identity.bundleID else {
            done("Run the installed \(Identity.appName).app to make it the default browser.")
            return
        }
        setDefault(Bundle.main.bundleURL, schemes: ["http", "https"], done: done)
    }

    @MainActor
    private static func setDefault(
        _ app: URL, schemes: [String], done: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        guard let scheme = schemes.first else {
            done(nil)
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { error in
            let message = error?.localizedDescription
            Task { @MainActor in
                if let message { done(message) } else { setDefault(app, schemes: Array(schemes.dropFirst()), done: done) }
            }
        }
    }

    /// Opens System Settings → Desktop & Dock, where the default browser is chosen.
    @MainActor
    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
