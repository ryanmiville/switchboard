import Foundation
import Testing

struct BuildTests {
    @Test func debugInstallBuildsFirstAndStopsOnBuildFailure() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let destination = fixture.root.appendingPathComponent("installed")
        let arguments = ["debug-install", "XCODEBUILD=/usr/bin/false", "INSTALL_DIR=\(destination.path)"]
        func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/make")
            process.arguments = arguments
            process.currentDirectoryURL = root
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        let plan = try run(["-n"] + arguments)
        #expect(plan.status == 0)
        let build = try #require(plan.output.range(of: "/usr/bin/false"))
        let install = try #require(plan.output.range(of: "ditto"))
        #expect(build.lowerBound < install.lowerBound)
        // Never execute an install test if it could write to the real Applications folder.
        try #require(!plan.output.contains("/Applications/"))
        #expect(try run(arguments).status != 0)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
