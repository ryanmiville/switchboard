import AppKit
import ScreenCaptureKit
import SwitchboardUI

/// `--shoot`: a fixture scene in the real settings window (or the Quick Switch panel), captured
/// from the screen with ScreenCaptureKit. Offscreen renders (`Renderer`) draw only the window's
/// content, so what the window server composites (the glass sidebar, the toolbar, the title bar,
/// the panel's glass) comes out blank; this captures what a person sees. It needs a screen and
/// permission to record it: CI's macOS runner has both, and its screen is 1x, so shots are too.
@MainActor
final class WindowShot {
    let scene: Scenes.Instance
    let dark: Bool
    let output: URL
    /// A golden to compare the shot with; a shot that differs writes `<output>-diff.png` and fails.
    let golden: URL?

    /// Pixels further apart than this in any channel count as changed.
    static let tolerance = 8
    /// A shot may differ from its golden in this share of its pixels: the text cursor blinks.
    static let allowedShare = 0.001

    init(scene name: String, dark: Bool, output: URL, golden: URL?) throws {
        scene = try Scenes.make(name)
        self.dark = dark
        self.output = output
        self.golden = golden
    }

    func take() async {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        do {
            let window = try await shownWindow()
            let pixels = try Pixels(try await capture(window))
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pixels.png().write(to: output)
            print(output.path)
            let failure = try golden.flatMap { try compare(pixels, with: $0) }
            scene.remove()
            if let failure {
                FileHandle.standardError.write(Data("\(failure)\n".utf8))
                exit(3)
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Switchboard: \(error)\n".utf8))
            scene.remove()
            exit(1)
        }
    }

    /// The scene's window once it is on screen, in front and settled.
    private func shownWindow() async throws -> NSWindow {
        // SwiftUI opens the window over a few run loop turns.
        var window: NSWindow?
        for _ in 0..<50 where window == nil {
            try await Task.sleep(for: .milliseconds(100))
            window = NSApp.windows.first {
                // The settings window has a title bar; the Quick Switch panel is borderless.
                $0.isVisible && $0.frame.width > 400
                    && $0.styleMask.contains(.titled) == (scene.kind != .picker)
            }
        }
        guard let window else { throw RenderError("The scene’s window never appeared.") }
        if scene.kind != .picker { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The glass and the key window's colours settle after it comes to the front.
        try await Task.sleep(for: .seconds(2))
        return window
    }

    private func capture(_ window: NSWindow) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let shared = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) })
        else { throw RenderError("ScreenCaptureKit doesn’t list the scene’s window.") }
        let configuration = SCStreamConfiguration()
        // In the screen's own pixels.
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: shared), configuration: configuration)
    }

    /// Why the shot doesn't match its golden, or nil when it does or there is no golden.
    private func compare(_ pixels: Pixels, with golden: URL) throws -> String? {
        guard let data = try? Data(contentsOf: golden) else { return nil }
        let expected = try Pixels(png: data)
        let name = output.lastPathComponent
        guard expected.width == pixels.width, expected.height == pixels.height else {
            return
                "\(name) is \(pixels.width)×\(pixels.height); its golden is \(expected.width)×\(expected.height)."
        }
        let (changed, diff) = pixels.difference(from: expected, tolerance: Self.tolerance)
        guard Double(changed) / Double(pixels.width * pixels.height) > Self.allowedShare else { return nil }
        let diffURL = output.deletingLastPathComponent()
            .appendingPathComponent(output.deletingPathExtension().lastPathComponent + "-diff.png")
        try diff.png().write(to: diffURL)
        return "\(name) differs from its golden in \(changed) pixels. Diff: \(diffURL.path)"
    }
}
