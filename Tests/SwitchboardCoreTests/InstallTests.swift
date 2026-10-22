import Foundation
import Testing

struct InstallTests {
    private func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func install(_ fixture: Fixture) throws -> Int32 {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try run(
            "/usr/bin/make",
            [
                "-C", root.path, "install", "XCODEBUILD=/usr/bin/true", "LSREGISTER=/usr/bin/true",
                "BUILD_DIR=\(fixture.root.appendingPathComponent("build").path)",
                "INSTALL_DIR=\(fixture.root.appendingPathComponent("installed").path)",
            ])
    }

    @Test func installReplacesTheWholeSignedBundleWithoutOldDebugLibraries() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let source = fixture.root.appendingPathComponent("build/Build/Products/Release/Switchboard.app")
        let browser = try fixture.browser()
        let executable = browser.appendingPathComponent("Contents/MacOS/ActualBrowser")
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        try #require(try run("/usr/bin/codesign", ["--force", "--sign", "-", browser.path]) == 0)
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: browser, to: source)
        let destination = fixture.root.appendingPathComponent("installed/Switchboard.app")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        let stale = destination.appendingPathComponent("Contents/MacOS/__preview.dylib")
        try Data("old debug library".utf8).write(to: stale)

        #expect(try install(fixture) == 0)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", destination.path]) == 0)
    }

    @Test func invalidReplacementLeavesTheInstalledAppUntouched() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let source = fixture.root.appendingPathComponent("build/Build/Products/Release/Switchboard.app")
        let destination = fixture.root.appendingPathComponent("installed/Switchboard.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("unsigned replacement".utf8).write(to: source.appendingPathComponent("new"))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let original = Data("keep installed app".utf8)
        try original.write(to: destination.appendingPathComponent("original"))

        #expect(try install(fixture) != 0)
        #expect(try Data(contentsOf: destination.appendingPathComponent("original")) == original)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("new").path))
    }
}
