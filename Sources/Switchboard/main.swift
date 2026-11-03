import AppKit
import SwitchboardUI

// The app binary.
//
// - Headless runs (`--list-scenes`, `--snap <png> --scene <name> [--theme dark]`) render the
//   fixture scenes only, and never read the real home.
// - Otherwise the app starts without a window, as a menu-bar app. Links arrive as Apple Events; a
//   launch that only delivers links quits shortly after the latest one and never shows the
//   menu-bar item. Settings opens from the item, or by opening the app again.

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--list-scenes") {
    for name in MainActor.assumeIsolated({ Scenes.names }) { print(name) }
    exit(0)
}

if let snapIndex = arguments.firstIndex(of: "--snap") {
    func value(after flag: String) -> String? {
        arguments.firstIndex(of: flag).flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }
    }
    guard arguments.indices.contains(snapIndex + 1), let scene = value(after: "--scene") else {
        FileHandle.standardError.write(
            Data("usage: Switchboard --snap <out.png> --scene <name> [--theme dark]\n".utf8))
        exit(2)
    }
    let output = URL(fileURLWithPath: arguments[snapIndex + 1])
    let dark = value(after: "--theme") == "dark"
    Task { @MainActor in
        do {
            try await Renderer.snap(scene: scene, dark: dark, to: output)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Switchboard: \(error)\n".utf8))
            exit(1)
        }
    }
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.run()
    }
    exit(0)
}

// `--describe-window` runs the real app, opens Settings, prints what macOS made of the window
// (`WindowReport`) and quits: renders can't show the system's toolbar, sidebar or glass.
if arguments.contains("--describe-window") {
    MainActor.assumeIsolated { AppDelegate.describesWindow = true }
}

// SwiftUI owns the app's windows and menu-bar item; AppDelegate the AppKit side.
SwitchboardApp.main()
