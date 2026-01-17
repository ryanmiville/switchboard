import Foundation

struct BrowserLauncher {
    let config: Config
    
    func launch(url: URL, profile: String) {
        // Get the executable path inside the .app bundle
        let browserPath = (config.browser as NSString).appendingPathComponent("Contents/MacOS")
        let appName = ((config.browser as NSString).lastPathComponent as NSString).deletingPathExtension
        let executablePath = (browserPath as NSString).appendingPathComponent(appName)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "--profile-directory=\(profile)",
            url.absoluteString
        ]
        
        do {
            try process.run()
        } catch {
            print("Failed to launch browser: \(error)")
        }
    }
}
