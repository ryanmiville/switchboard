import Foundation
import Testing

@testable import SwitchboardCore

struct ConfigTests {
    @Test func missingFileUsesDefaults() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let config = try Config.loadOrDefault(from: fixture.configURL)
        #expect(config.defaultProfile == "Default")
        #expect(!FileManager.default.fileExists(atPath: fixture.configURL.path))
    }

    @Test func malformedFileIsNotTreatedAsMissing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = Data("{ broken JSON".utf8)
        try original.write(to: fixture.configURL)
        #expect(throws: (any Error).self) {
            _ = try Config.loadOrDefault(from: fixture.configURL)
        }
        #expect(try Data(contentsOf: fixture.configURL) == original)
    }

    @Test func existingConfigFormatRoundTrips() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = Data(
            #"{"browser":"/Applications/Helium.app","defaultProfile":"Default","routes":[{"condition":"exact","value":"https://example.com","profile":"Profile 1"}]}"#
                .utf8)
        try original.write(to: fixture.configURL)
        let config = try Config.load(from: fixture.configURL)
        try config.save(to: fixture.configURL)
        let loaded = try Config.load(from: fixture.configURL)
        #expect(loaded.browser == config.browser)
        #expect(loaded.routes.first?.condition == .exact)
        #expect(loaded.routes.first?.profile == "Profile 1")
        #expect(loaded.routes.first?.browser == nil)
    }

    @Test func perRuleBrowserIsPreservedInJSON() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let json = Data(
            #"{"browser":"/Applications/Helium.app","defaultProfile":"Default","routes":[{"condition":"domain","value":"gitlab.com","browser":"/Applications/Google Chrome.app","profile":"Profile 2"}]}"#
                .utf8)
        try json.write(to: fixture.configURL)
        let config = try Config.load(from: fixture.configURL)
        try config.save(to: fixture.configURL)
        let saved = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.configURL)) as? [String: Any])
        let route = try #require((saved["routes"] as? [[String: Any]])?.first)
        #expect(route["browser"] as? String == "/Applications/Google Chrome.app")
    }

    @Test func pickerSectionRoundTrips() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let json = Data(
            #"{"browser":"/Applications/Helium.app","defaultProfile":"Default","routes":[],"picker":{"shortcut":{"keyCode":40,"modifiers":256,"key":"K"},"favorites":[{"browser":"/Applications/Google Chrome.app","profile":"Profile 2","name":"Work"}],"destinations":[]}}"#
                .utf8)
        try json.write(to: fixture.configURL)
        let config = try Config.load(from: fixture.configURL)
        try config.save(to: fixture.configURL)
        let picker = try #require(try Config.load(from: fixture.configURL).picker)
        #expect(picker.shortcut == KeyboardShortcut(keyCode: 40, modifiers: 256, key: "K"))
        #expect(
            picker.favorites == [
                PickerFavorite(browser: "/Applications/Google Chrome.app", profile: "Profile 2", name: "Work")
            ])
        // An empty selection hides everything and must not turn back into "show all".
        #expect(picker.destinations == [])
        #expect(PickerSettings().shortcut == .default)
    }
}
