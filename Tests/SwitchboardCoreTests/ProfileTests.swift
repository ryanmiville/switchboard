import Foundation
import Testing

@testable import SwitchboardCore

struct ProfileTests {
    @Test(arguments: [
        ("com.google.Chrome", "Google/Chrome"),
        ("com.google.Chrome.beta", "Google/Chrome Beta"),
        ("com.google.Chrome.dev", "Google/Chrome Dev"),
        ("com.google.Chrome.canary", "Google/Chrome Canary"),
        ("org.chromium.Chromium", "Chromium"),
        ("com.brave.Browser", "BraveSoftware/Brave-Browser"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("net.imput.helium", "net.imput.helium"),
    ])
    func browserSpecificFolders(id: String, folder: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser(id: id)
        try fixture.profiles(["Default": "Personal", "Profile 1": "Work"], folder: folder)
        let profiles = try BrowserProfiles(homeDirectory: fixture.root).profiles(browserPath: browser.path)
        #expect(profiles.map(\.directory) == ["Default", "Profile 1"])
        #expect(profiles.last?.name == "Work")
    }

    @Test func stableDirectorySurvivesRenamesAndNameCollisions() throws {
        let profiles = [
            Profile(name: "Profile 1", directory: "Default"),
            Profile(name: "Renamed", directory: "Profile 1"),
        ]
        #expect(try BrowserProfiles.directory(for: "Profile 1", in: profiles) == "Profile 1")
        #expect(throws: ProfileError.self) { try BrowserProfiles.directory(for: "Old name", in: profiles) }
    }

    @Test func legacyNamesMustBeUnambiguous() throws {
        let profiles = [
            Profile(name: "Work", directory: "Profile 1"), Profile(name: "Work", directory: "Profile 2"),
        ]
        #expect(throws: ProfileError.self) { try BrowserProfiles.directory(for: "Work", in: profiles) }
        #expect(try BrowserProfiles.directory(for: "Profile 2", in: profiles) == "Profile 2")
    }

    @Test func malformedLocalStateDoesNotInventProfiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let browser = try fixture.browser()
        try fixture.profiles(["Default": "Personal"])
        try Data("{ broken".utf8).write(
            to: fixture.root.appendingPathComponent("Library/Application Support/Google/Chrome/Local State"))
        #expect(throws: (any Error).self) {
            try BrowserProfiles(homeDirectory: fixture.root).profiles(browserPath: browser.path)
        }
    }
}
