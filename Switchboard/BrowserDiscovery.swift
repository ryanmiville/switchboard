import AppKit

struct InstalledBrowser: Identifiable, Hashable {
    let url: URL
    let name: String
    let icon: NSImage
    var id: URL { url }
    var path: String { url.path }
    
    static func == (lhs: InstalledBrowser, rhs: InstalledBrowser) -> Bool {
        lhs.url == rhs.url
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

struct BrowserDiscovery {
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "com.google.Chrome.beta",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.opera.Opera",
        "com.opera.OperaBeta",
        "com.opera.OperaDeveloper",
        "org.chromium.Chromium",
        "com.vivaldi.Vivaldi",
        "com.keksbay.Arc",
        "net.imput.helium",
    ]
    
    static func chromiumBrowsers() -> [InstalledBrowser] {
        guard let httpURL = URL(string: "http://example.com") else { return [] }
        return NSWorkspace.shared
            .urlsForApplications(toOpen: httpURL)
            .filter { isChromium($0) }
            .map { InstalledBrowser(url: $0, name: displayName($0), icon: icon($0)) }
    }
    
    private static func isChromium(_ url: URL) -> Bool {
        guard let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return false }
        return chromiumBundleIDs.contains(id)
    }
    
    private static func displayName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
    }
    
    private static func icon(_ url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
