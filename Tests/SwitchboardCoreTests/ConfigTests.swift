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
    }
}
