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
    // The settings model, link routing for the app's lifetime and the Quick Switch model, without
    // SwiftUI, so they are tested on Linux too.
    .target(name: "SwitchboardEditor", dependencies: ["SwitchboardCore"], swiftSettings: strict),

    .testTarget(
        name: "SwitchboardCoreTests", dependencies: ["SwitchboardCore", "SwitchboardFixtures"],
        swiftSettings: strict),
    // Runs the built switchboard-next binary against temporary homes.
    .testTarget(
        name: "CLITests", dependencies: ["switchboard-next", "SwitchboardCore", "SwitchboardFixtures"],
        swiftSettings: strict),
    .testTarget(
        name: "EditorTests", dependencies: ["SwitchboardEditor", "SwitchboardCore", "SwitchboardFixtures"],
        swiftSettings: strict),
]

#if os(macOS)
    targets += [
        // AppKit glue: the menu-bar item, launch at login, reading the current tab, the global
        // shortcut, and whether this app is the default browser.
        .target(
            name: "SwitchboardMac", dependencies: ["SwitchboardCore", "SwitchboardEditor"],
            swiftSettings: strict),
        // The SwiftUI settings window and Quick Switch panel, and the named scenes renders start from.
        .target(
            name: "SwitchboardUI",
            dependencies: ["SwitchboardCore", "SwitchboardEditor", "SwitchboardFixtures"],
            swiftSettings: strict),
        // The app binary: wiring, link delivery, the app's lifetime, and headless scene renders.
        .executableTarget(
            name: "Switchboard",
            dependencies: ["SwitchboardCore", "SwitchboardEditor", "SwitchboardMac", "SwitchboardUI"],
            swiftSettings: strict),
        // Every scene rendered in light and dark and compared with its golden.
        .testTarget(
            name: "UITests", dependencies: ["SwitchboardUI", "SwitchboardEditor", "SwitchboardFixtures"],
            exclude: ["Goldens"], swiftSettings: strict),
    ]
#endif

#if os(macOS)
    let appProducts: [Product] = [.executable(name: "Switchboard", targets: ["Switchboard"])]
#else
    let appProducts: [Product] = []
#endif

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "switchboard-next", targets: ["switchboard-next"])] + appProducts,
    dependencies: [.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")],
    targets: targets,
    swiftLanguageModes: [.v6]
)
