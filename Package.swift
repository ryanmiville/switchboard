// swift-tools-version: 6.0
import PackageDescription

// The module graph is the architecture (docs/architecture.md): dependencies point down only, and
// SwiftPM refuses an import a target doesn't declare. Foundation-only targets build and test on
// Linux too; the AppKit and SwiftUI targets are added on macOS only.

let strict: [SwiftSetting] = [.unsafeFlags(["-warnings-as-errors"])]
let argumentParser = Target.Dependency.product(name: "ArgumentParser", package: "swift-argument-parser")

var targets: [Target] = [
    // Every rule and file format, browser discovery and launching. Foundation only.
    .target(name: "SwitchboardCore", swiftSettings: strict),
    // Fixture homes and browsers for tests and scenes: real app bundles whose program records its
    // arguments instead of opening anything.
    .target(name: "SwitchboardFixtures", dependencies: ["SwitchboardCore"], swiftSettings: strict),
    // The CLI's commands, as a library the binary (and later the app) runs.
    .target(
        name: "SwitchboardCLI", dependencies: ["SwitchboardCore", argumentParser], swiftSettings: strict),
    .executableTarget(name: "switchboard-next", dependencies: ["SwitchboardCLI"], swiftSettings: strict),

    .testTarget(
        name: "SwitchboardCoreTests", dependencies: ["SwitchboardCore", "SwitchboardFixtures"],
        swiftSettings: strict),
    // Runs the built switchboard-next binary against temporary homes.
    .testTarget(
        name: "CLITests", dependencies: ["switchboard-next", "SwitchboardCore", "SwitchboardFixtures"],
        swiftSettings: strict),
]

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "switchboard-next", targets: ["switchboard-next"])],
    dependencies: [.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")],
    targets: targets,
    swiftLanguageModes: [.v6]
)
