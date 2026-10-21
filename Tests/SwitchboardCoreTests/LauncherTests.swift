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
            config: Config(browser: browser.path, defaultProfile: "Default", routes: []),
            profileStore: BrowserProfiles(homeDirectory: fixture.root),
            runProcess: { executable, arguments in
                #expect(executable.lastPathComponent == "ActualBrowser")
                received = arguments
            }
        )
        try launcher.launch(url: url, profileName: "Work")
        #expect(received == ["--profile-directory=Profile 1", url.absoluteString])
    }

    @Test func processFailuresReachCaller() throws {
        struct Failure: Error {}
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        let launcher = BrowserLauncher(
            config: Config(browser: browser.path, defaultProfile: "Default", routes: []),
            profileStore: BrowserProfiles(homeDirectory: fixture.root),
            runProcess: { _, _ in throw Failure() }
        )
        #expect(throws: Failure.self) {
            try launcher.launch(url: #require(URL(string: "https://example.com")), profileName: "Default")
        }
    }

    @Test(arguments: ["--incognito", "file:///tmp/a", "javascript:alert(1)", "https:relative"])
    func nonWebURLsCannotBecomeBrowserArguments(value: String) throws {
        let launcher = BrowserLauncher(
            config: .defaults,
            runProcess: { _, _ in
                Issue.record("Invalid URL reached process runner")
            })
        #expect(throws: (any Error).self) {
            try launcher.launch(url: #require(URL(string: value)), profileName: "Default")
        }
    }
}
