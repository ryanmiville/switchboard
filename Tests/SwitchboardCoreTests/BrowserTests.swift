import Foundation
import SwitchboardFixtures
import Testing

@testable import SwitchboardCore

// Browser discovery, profiles and launching against fixture app bundles in a temporary home.
struct BrowserTests {
    @Test func installedBrowsersAreFoundByBundleIdentifierAndSortedByName() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let chrome = try fixture.installBrowser(.chrome, name: "Google Chrome")
        let helium = try fixture.installBrowser(.helium, name: "Helium")
        // Not a Chromium browser Switchboard supports, so it is ignored.
        let other = fixture.applications.appendingPathComponent("Notes.app/Contents")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "com.apple.Notes", "CFBundleExecutable": "Notes"],
            format: .xml,
            options: 0
        ).write(to: other.appendingPathComponent("Info.plist"))

        let installed = fixture.browsers.installed()
        #expect(installed.map(\.locator) == [chrome, helium])
        #expect(installed[0].family == .chrome)
        #expect(installed[0].answers(to: "chrome"))
        #expect(installed[0].executable.path == chrome + "/Contents/MacOS/GoogleChrome")
        #expect(
            installed[1].userData.path == fixture.home.path + "/Library/Application Support/net.imput.helium")
        #expect(fixture.browsers.at(chrome + "/") == installed[0], "trailing slashes are ignored")
        #expect(fixture.browsers.displayName("/nowhere/Arc.app") == "Arc")
    }

    @Test func localStateListsDefaultFirstThenByName() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let helium = try fixture.installBrowser(
            .helium, name: "Helium",
            profiles: [("Profile 2", "alpha"), ("Default", "Zed"), ("Profile 1", "beta")])
        let info = try #require(fixture.browsers.at(helium))
        #expect(
            try Profiles.read(info).map { [$0.directory, $0.name] } == [
                ["Default", "Zed"], ["Profile 2", "alpha"], ["Profile 1", "beta"],
            ])
        try FileManager.default.removeItem(at: info.userData.appendingPathComponent("Local State"))
        #expect(try Profiles.read(info) == [Profile(directory: "Default", name: "Default")])
    }

    @Test func aDirectoryIdentifierWinsAndAmbiguousNamesAreRefused() throws {
        let profiles = [
            Profile(directory: "Default", name: "Ryan"), Profile(directory: "Profile 1", name: "Profile 2"),
            Profile(directory: "Profile 2", name: "Work"), Profile(directory: "Profile 3", name: "Work"),
        ]
        #expect(try Profiles.directory("Profile 2", in: profiles) == "Profile 2")
        #expect(try Profiles.directory("Ryan", in: profiles) == "Default")
        #expect(throws: ProfileError.ambiguous("Work")) { try Profiles.directory("Work", in: profiles) }
        #expect(throws: ProfileError.missing("Nobody")) { try Profiles.directory("Nobody", in: profiles) }
        #expect(throws: ProfileError.selectionRequired) { try Profiles.directory("", in: profiles) }
    }

    @Test func theSameDirectoryInTwoBrowsersResolvesWithinEachBrowser() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let chrome = try fixture.installBrowser(
            .chrome, name: "Google Chrome", profiles: [("Default", "Work")])
        let helium = try fixture.installBrowser(
            .helium, name: "Helium", profiles: [("Default", "Ryan"), ("Profile 1", "Work")])
        let config = Config(
            browser: helium, defaultProfile: "Work",
            rules: [
                Rule(.domain, "acme.com", profile: "Work", browser: chrome),
                Rule(.domain, "a.com", profile: "Ryan"),
            ])
        let normalized = try Profiles.normalized(config, fixture.browsers)
        #expect(normalized.defaultProfile == "Profile 1")
        #expect(normalized.rules.map(\.profile) == ["Default", "Default"])
    }

    @Test func aLaunchRunsTheExecutableWithTheProfileDirectoryAndTheExactLink() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let chrome = try fixture.installBrowser(
            .chrome, name: "Google Chrome", profiles: [("Profile 3", "Work")])
        let link = "https://Example.com/a%2Fb?q=caf\u{E9}#Top"
        try Launch.launch(link, at: Destination(browser: chrome, profile: "Work"), browsers: fixture.browsers)
        #expect(fixture.waitForLaunches(1) == [["--profile-directory=Profile 3", link]])
    }

    @Test func launchesThatCantRunAreRefusedBeforeStartingAnything() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        let chrome = try fixture.installBrowser(.chrome, name: "Google Chrome")
        let browsers = fixture.browsers
        let destination = Destination(browser: chrome, profile: "Default")
        #expect(throws: LaunchError.invalidURL) {
            try Launch.command("github.com", at: destination, browsers: browsers)
        }
        #expect(throws: LaunchError.profile(.missing("Nobody"))) {
            try Launch.command(
                "https://x.com", at: Destination(browser: chrome, profile: "Nobody"), browsers: browsers)
        }
        #expect(throws: LaunchError.profile(.browserUnavailable(""))) {
            try Launch.command(
                "https://x.com", at: Destination(browser: "", profile: "Default"), browsers: browsers)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: chrome + "/Contents/MacOS/GoogleChrome")
        #expect(throws: LaunchError.notExecutable(chrome + "/Contents/MacOS/GoogleChrome")) {
            try Launch.command("https://x.com", at: destination, browsers: browsers)
        }
        #expect(fixture.recordedLaunches().isEmpty)
    }

    @Test func aLaunchStillBeingWrittenIsNotCountedYet() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        try Data("--profile-directory=Default\thttps://a.com\t\n--profile-directory=Work\t".utf8)
            .write(to: fixture.launchLog)
        #expect(fixture.recordedLaunches() == [["--profile-directory=Default", "https://a.com"]])
    }

    @Test func theOpenAndLastUsedProfilesAreReadFromLocalState() throws {
        let fixture = try TemporaryHome()
        defer { fixture.remove() }
        _ = try fixture.installBrowser(
            .helium, name: "Helium", profiles: [("Default", "Ryan"), ("Profile 1", "Work")])
        let helium = try #require(fixture.browsers.installed().first)
        #expect(Profiles.activity(helium) == ProfileActivity())
        try fixture.writeLocalState(
            of: helium, [("Default", "Ryan"), ("Profile 1", "Work")], open: ["Default", "Profile 1"],
            lastUsed: "Profile 1")
        #expect(
            Profiles.activity(helium)
                == ProfileActivity(open: ["Default", "Profile 1"], lastUsed: "Profile 1"))
        try Data("not json".utf8).write(to: helium.userData.appendingPathComponent("Local State"))
        #expect(Profiles.activity(helium) == ProfileActivity())
    }
}
