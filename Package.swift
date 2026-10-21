// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SwitchboardCore",
            path: "Switchboard",
            exclude: [
                "Assets.xcassets", "ContentView.swift", "Info.plist",
                "Switchboard.entitlements", "SwitchboardApp.swift",
            ]
        ),
        .testTarget(name: "SwitchboardCoreTests", dependencies: ["SwitchboardCore"]),
    ],
    swiftLanguageModes: [.v6]
)
