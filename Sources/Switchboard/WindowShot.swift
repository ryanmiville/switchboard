import AppKit
import ScreenCaptureKit
import SwitchboardUI

/// `--shoot`: the settings window of a fixture scene, captured from the screen. Offscreen renders
/// (`Renderer`) draw only the window's content, so the parts the window server composites (the
/// glass sidebar, the toolbar, the title bar) come out blank; this captures what a person sees.
@MainActor
final class WindowShot {
    let scene: Scenes.Instance
    let dark: Bool
    let output: URL

    init(scene name: String, dark: Bool, output: URL) throws {
        scene = try Scenes.make(name)
        self.dark = dark
        self.output = output
    }

    func take() async {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        do {
            // SwiftUI opens the window over a few run loop turns, and the glass settles after it.
            var window: NSWindow?
            for _ in 0..<40 where window == nil {
                try await Task.sleep(for: .milliseconds(100))
                window = NSApp.windows.first { $0.isVisible && $0.title != "" && $0.frame.width > 400 }
            }
            guard let window else { throw RenderError("The settings window never appeared.") }
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .seconds(2))
            print("window \(window.windowNumber) \(Int(window.frame.width))×\(Int(window.frame.height))")
            let image = try await capture(window)
            let pixels = try Pixels(image)
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pixels.png().write(to: output)
            print("shot \(image.width)×\(image.height) \(output.path)")
            // Kept open a little longer, so a script can capture the same window with screencapture.
            try await Task.sleep(for: .seconds(3))
            scene.remove()
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Switchboard: \(error)\n".utf8))
            scene.remove()
            exit(1)
        }
    }

    private func capture(_ window: NSWindow) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let shared = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) })
        else { throw RenderError("ScreenCaptureKit doesn’t list the settings window.") }
        let filter = SCContentFilter(desktopIndependentWindow: shared)
        let configuration = SCStreamConfiguration()
        // In the screen's own pixels: CI's virtual display is 1x, so this is 1x there.
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
