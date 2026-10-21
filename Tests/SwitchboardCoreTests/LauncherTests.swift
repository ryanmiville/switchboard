import Foundation
import Testing

@testable import SwitchboardCore

struct LauncherTests {
    @Test func renamedBundleUsesDeclaredExecutableAndPreservesURL() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal", "Profile 1": "Work"])
        let url = try #require(URL(string: "https://example.com/Case?a=b%20c&x=1#fragment"))
        var received: [String] = []
        let launcher = BrowserLauncher(
            profileStore: BrowserProfiles(homeDirectory: fixture.root),
            runProcess: { executable, arguments in
                #expect(executable.lastPathComponent == "ActualBrowser")
                received = arguments
            }
        )
        try launcher.launch(url: url, destination: Destination(browser: browser.path, profile: "Work"))
        #expect(received == ["--profile-directory=Profile 1", url.absoluteString])
    }

    @Test func processFailuresReachCaller() throws {
        struct Failure: Error {}
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        let launcher = BrowserLauncher(
            profileStore: BrowserProfiles(homeDirectory: fixture.root),
            runProcess: { _, _ in throw Failure() }
        )
        #expect(throws: Failure.self) {
            try launcher.launch(
                url: #require(URL(string: "https://example.com")),
                destination: Destination(browser: browser.path, profile: "Default"))
        }
    }

    @Test(arguments: ["--incognito", "file:///tmp/a", "javascript:alert(1)", "https:relative"])
    func nonWebURLsCannotBecomeBrowserArguments(value: String) throws {
        let launcher = BrowserLauncher(
            runProcess: { _, _ in
                Issue.record("Invalid URL reached process runner")
            })
        #expect(throws: (any Error).self) {
            try launcher.launch(
                url: #require(URL(string: value)),
                destination: Destination(browser: "/fixture.app", profile: "Default"))
        }
    }

    @Test func routedLinksLaunchChromeAndHeliumWithTheirOwnProfiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try fixture.browser(executable: "Google Chrome", name: "Chrome")
        let helium = try fixture.browser(id: "net.imput.helium", executable: "Helium", name: "Helium")
        try fixture.profiles(["Default": "Chrome Personal", "Profile 3": "Chrome Work"])
        try fixture.profiles(["Default": "Ryan"], folder: "net.imput.helium")
        let config = Config(
            browser: helium.path, defaultProfile: "Default",
            routes: [
                Route(condition: .domain, value: "gitlab.com", profile: "Profile 3", browser: chrome.path)
            ])
        var executables: [URL] = []
        var arguments: [[String]] = []
        let launcher = BrowserLauncher(
            profileStore: BrowserProfiles(homeDirectory: fixture.root),
            runProcess: {
                executables.append($0)
                arguments.append($1)
            })
        for value in ["https://gitlab.com/example?case=Mixed#fragment", "https://example.com/default"] {
            let url = try #require(URL(string: value))
            try launcher.launch(url: url, destination: Router(config: config).route(url: url))
        }
        #expect(executables.map(\.lastPathComponent) == ["Google Chrome", "Helium"])
        #expect(
            executables.map { $0.standardizedFileURL.path } == [
                chrome.appendingPathComponent("Contents/MacOS/Google Chrome").path,
                helium.appendingPathComponent("Contents/MacOS/Helium").path,
            ])
        #expect(
            arguments == [
                ["--profile-directory=Profile 3", "https://gitlab.com/example?case=Mixed#fragment"],
                ["--profile-directory=Default", "https://example.com/default"],
            ])
    }
}
