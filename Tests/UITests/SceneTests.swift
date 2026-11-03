import AppKit
import Foundation
import SwitchboardCore
import Testing

@testable import SwitchboardUI

// Every scene drawn in light and dark into .build/snapshots, and compared with its golden in
// Tests/UITests/Goldens when one exists. Pixels depend on the macOS version, so goldens are
// compared only when SNAPSHOT_COMPARE=1; SNAPSHOT_RECORD=1 rewrites them. CI uploads the renders.
@MainActor
@Suite(.serialized)
struct SceneTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let goldens = root.appendingPathComponent("Goldens")
    static let output = root.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/snapshots")

    @Test(arguments: Scenes.names)
    func everySceneDrawsInLightAndDark(scene name: String) async throws {
        for dark in [false, true] {
            let scene = try Scenes.make(name)
            defer { scene.remove() }
            let pixels = try await Renderer.render(scene.view, size: scene.size, dark: dark)
            try check("\(name)-\(dark ? "dark" : "light")", pixels)
        }
    }

    @Test func scenesNeverUseTheRealHome() throws {
        for name in Scenes.names {
            let scene = try Scenes.make(name)
            defer { scene.remove() }
            let path = scene.settings.editor.home.path
            #expect(path.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path))
            #expect(scene.settings.editor.store.url.path.hasPrefix(path))
            #expect(scene.picker.store.url.path.hasPrefix(path))
        }
    }

    @Test func theRuleSheetShowsWhyADraftCantBeSaved() throws {
        let scene = try Scenes.make("rule-error")
        defer { scene.remove() }
        #expect(scene.settings.draft?.error?.contains("isn’t a domain") == true)
    }

    @Test func aConflictKeepsTheEditsAndOffersBothChoices() throws {
        let scene = try Scenes.make("conflict")
        defer { scene.remove() }
        #expect(scene.settings.editor.conflict)
        #expect(scene.settings.editor.config.defaultProfile == "Profile 1")
    }

    private func check(_ name: String, _ pixels: Pixels) throws {
        let environment = ProcessInfo.processInfo.environment
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        let png = try pixels.png()
        try png.write(to: Self.output.appendingPathComponent("\(name).png"))
        let golden = Self.goldens.appendingPathComponent("\(name).png")
        if environment["SNAPSHOT_RECORD"] == "1" {
            try png.write(to: golden)
            return
        }
        guard environment["SNAPSHOT_COMPARE"] == "1", let data = try? Data(contentsOf: golden) else { return }
        let expected = try Pixels(png: data)
        guard expected.width == pixels.width, expected.height == pixels.height else {
            Issue.record(
                "\(name) is \(pixels.width)×\(pixels.height); its golden is \(expected.width)×\(expected.height)."
            )
            return
        }
        let (changed, diff) = pixels.difference(from: expected, tolerance: 8)
        let share = Double(changed) / Double(pixels.width * pixels.height)
        guard share > 0.001 else { return }
        let diffURL = Self.output.appendingPathComponent("\(name)-diff.png")
        try diff.png().write(to: diffURL)
        Issue.record("\(name) differs from its golden in \(changed) pixels. Diff: \(diffURL.path)")
    }
}
