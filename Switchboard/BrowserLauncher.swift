import Foundation

struct BrowserLauncher {
    let config: Config
    var profileStore = BrowserProfiles()
    var runProcess: (URL, [String]) throws -> Void = { executable, arguments in
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
    }

    func launch(url: URL, profileName: String) throws {
        guard Router.isWebURL(url) else { throw LaunchError.invalidURL }
        guard let executable = Bundle(path: config.browser)?.executableURL,
            FileManager.default.isExecutableFile(atPath: executable.path)
        else { throw ProfileError.browserUnavailable }
        let profiles = try profileStore.profiles(browserPath: config.browser)
        let directory = try BrowserProfiles.directory(for: profileName, in: profiles)
        try runProcess(executable, ["--profile-directory=\(directory)", url.absoluteString])
    }
}

enum LaunchError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        "Switchboard can only open complete HTTP or HTTPS links."
    }
}
