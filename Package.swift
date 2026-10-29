// swift-tools-version: 6.0
import PackageDescription

// Linux has no AppKit, SwiftUI, Carbon, Combine or ServiceManagement, so `make verify-linux` builds the
// Foundation-only core and the tests that run without them. macOS always builds and tests everything.
#if os(Linux)
    let appleOnlySources = [
        "BrowserDiscovery.swift", "ConfigViewModel.swift", "CurrentTabReader.swift", "GlobalShortcut.swift",
        "LoginItem.swift", "PickerSettings.swift", "ShortcutRecorder.swift", "SwitchboardApp.swift",
        "TabPicker.swift",
    ]
    // InstallTests needs codesign. LauncherTests needs Bundle.executableURL, which Linux Foundation
    // doesn't resolve for macOS app bundles.
    let appleOnlyTests = [
        "ConfigViewModelTests.swift", "CurrentTabTests.swift", "InstallTests.swift", "LauncherTests.swift",
        "LoginItemTests.swift", "PickerTests.swift", "ReopenTests.swift",
    ]
#else
    let appleOnlySources: [String] = []
    let appleOnlyTests: [String] = []
#endif

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "switchboard", targets: ["switchboard"])],
    dependencies: [.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")],
    targets: [
        // Xcode compiles the shipped `switchboard` tool as one module from the Foundation-only core files
        // plus Switchboard/CLI, so the package keeps the command definitions in the same module too.
        .target(
            name: "SwitchboardCore",
            dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Switchboard",
            exclude: [
                "Assets.xcassets", "ContentView.swift", "Info.plist",
                "Switchboard.entitlements",
            ] + appleOnlySources
        ),
        .executableTarget(name: "switchboard", dependencies: ["SwitchboardCore"], path: "CLI"),
        .testTarget(
            name: "SwitchboardCoreTests", dependencies: ["SwitchboardCore"], exclude: appleOnlyTests),
    ],
    swiftLanguageModes: [.v6]
)
