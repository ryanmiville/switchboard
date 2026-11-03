import AppKit
import SwitchboardCore

/// Whether this app is the system's default browser, and asking macOS to make it so. macOS shows
/// its own confirmation; the person can also choose in System Settings → Desktop & Dock.
public enum DefaultBrowser {
    static let schemes = ["http", "https"]

    /// This app opens both http and https links.
    @MainActor
    public static var isDefault: Bool { schemes.allSatisfy(handles) }

    /// Asks macOS to open http and https links with this app. `done` gets why it failed, if it did.
    ///
    /// macOS confirms the change once and then sets both schemes itself, so a later request for a
    /// scheme it already changed can fail with an unhelpful error. Schemes that already open here
    /// are skipped, and after an error the result is checked before anything is reported.
    @MainActor
    public static func makeDefault(done: @escaping @MainActor @Sendable (String?) -> Void) {
        guard Bundle.main.bundleIdentifier == Identity.bundleID else {
            done("Run the installed \(Identity.appName).app to make it the default browser.")
            return
        }
        setDefault(Bundle.main.bundleURL, schemes: schemes, done: done)
    }

    @MainActor
    private static func setDefault(
        _ app: URL, schemes: [String], done: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        guard let scheme = schemes.first(where: { !handles($0) }) else {
            done(nil)
            return
        }
        let rest = schemes.filter { $0 != scheme }
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { error in
            let message = error?.localizedDescription
            Task { @MainActor in
                if let message, !handles(scheme) {
                    done(
                        "macOS didn’t make \(Identity.appName) open \(scheme) links (\(message)). Choose it in System Settings → Desktop & Dock → Default web browser."
                    )
                } else {
                    setDefault(app, schemes: rest, done: done)
                }
            }
        }
    }

    /// Whether macOS sends `scheme` links to this app now.
    @MainActor
    static func handles(_ scheme: String) -> Bool {
        guard let probe = URL(string: "\(scheme)://example.com"),
            let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Identity.bundleID
    }

    /// Opens System Settings → Desktop & Dock, where the default browser is chosen.
    @MainActor
    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
