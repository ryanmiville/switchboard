import Foundation

struct BrowserLauncher {
    let config: Config
    
    /// Launch browser with profile name (display name, e.g., "Ryan")
    func launch(url: URL, profileName: String) {
        let directory = Self.profileDirectory(forName: profileName, browserPath: config.browser)
        
        // Get the executable path inside the .app bundle
        let browserPath = (config.browser as NSString).appendingPathComponent("Contents/MacOS")
        let appName = ((config.browser as NSString).lastPathComponent as NSString).deletingPathExtension
        let executablePath = (browserPath as NSString).appendingPathComponent(appName)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "--profile-directory=\(directory)",
            url.absoluteString
        ]
        
        do {
            try process.run()
        } catch {
            print("Failed to launch browser: \(error)")
        }
    }
    
    /// Resolves a profile display name to its directory identifier
    static func profileDirectory(forName name: String, browserPath: String) -> String {
        guard let bundleId = Bundle(path: browserPath)?.bundleIdentifier else {
            return name
        }
        
        let localStateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(bundleId)/Local State")
        
        guard let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return name
        }
        
        for (directory, info) in infoCache {
            guard let profileInfo = info as? [String: Any],
                  let profileName = profileInfo["name"] as? String else { continue }
            if profileName == name {
                return directory
            }
        }
        
        return name // Fallback: assume name is directory
    }
}
