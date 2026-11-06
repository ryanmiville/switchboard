import Foundation

// Opening a link in a browser profile. The browser's executable is run directly with an argument
// array (`--profile-directory=<dir> <link>`), never through `open -a`, so the profile is honoured
// when the browser is already running. The link is passed exactly as it arrived.
//
// Safari is the exception: it takes no arguments and runs as one process, so a second copy of its
// executable can't hand a link to the first. It is opened with `open -a <Safari.app> <link>`, which
// asks Launch Services to give the running Safari the link. Safari has a single profile here (see
// Profiles.swift), so nothing is lost.

public enum LaunchError: Error, Equatable, CustomStringConvertible {
    case invalidURL
    case profile(ProfileError)
    case notExecutable(String)
    case spawn(String)

    public var description: String {
        switch self {
        case .invalidURL: "\(Identity.appName) can only open complete HTTP or HTTPS links and local files."
        case .profile(let error): error.description
        case .notExecutable(let path):
            "The browser’s program at \(path) can’t be run. Reinstall the browser or choose another."
        case .spawn(let why): "The browser couldn’t be started. \(why)"
        }
    }
}

public enum Launch {
    /// The program and arguments that open `link` at `destination`, after checking both.
    public static func command(_ link: String, at destination: Destination, browsers: Browsers)
        throws(LaunchError) -> (program: URL, arguments: [String])
    {
        guard Link.isWeb(link) || Link.isLocalFile(link) else { throw .invalidURL }
        guard let browser = browsers.at(destination.browser) else {
            throw .profile(.browserUnavailable(destination.browser))
        }
        guard isExecutable(browser.executable) else { throw .notExecutable(browser.executable.path) }
        let directory: String
        do {
            directory = try Profiles.directory(destination.profile, in: try Profiles.read(browser))
        } catch {
            throw .profile(error)
        }
        guard browser.family.isChromium else { return (browsers.opener, ["-a", browser.locator, link]) }
        return (browser.executable, ["--profile-directory=\(directory)", link])
    }

    /// Starts the browser and returns once it has started. Foundation reaps the child when it
    /// exits, so a resident app collects no zombies.
    public static func launch(_ link: String, at destination: Destination, browsers: Browsers)
        throws(LaunchError)
    {
        let (program, arguments) = try command(link, at: destination, browsers: browsers)
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw .spawn("\(program.path): \(error.localizedDescription)")
        }
    }

    static func isExecutable(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let permissions = attributes[.posixPermissions] as? NSNumber
        else { return false }
        return permissions.intValue & 0o111 != 0
    }
}
