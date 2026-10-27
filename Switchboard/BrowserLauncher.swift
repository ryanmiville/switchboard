import Foundation

struct BrowserLauncher {
    var profileStore = BrowserProfiles()
    var runProcess: (URL, [String]) throws -> Void = { executable, arguments in
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
    }

    func launch(url: URL, destination: Destination) throws {
        guard Router.isWebURL(url) || Router.isLocalFileURL(url) else { throw LaunchError.invalidURL }
        guard let executable = Bundle(path: destination.browser)?.executableURL,
            FileManager.default.isExecutableFile(atPath: executable.path)
        else { throw ProfileError.browserUnavailable }
        let profiles = try profileStore.profiles(browserPath: destination.browser)
        let directory = try BrowserProfiles.directory(for: destination.profile, in: profiles)
        try runProcess(executable, ["--profile-directory=\(directory)", url.absoluteString])
    }
}

enum LaunchError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        "Switchboard can only open complete HTTP or HTTPS links and local files."
    }
}
