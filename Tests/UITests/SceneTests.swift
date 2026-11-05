import AppKit
import Foundation
import SwitchboardCore
import SwitchboardEditor
import Testing

@testable import SwitchboardUI

// Every scene drawn in light and dark into .build/snapshots, and compared with its golden in
// Tests/UITests/Goldens when one exists.
//
// - SNAPSHOT_COMPARE=1 compares. CI does; goldens are recorded on CI's runner, since pixels depend
//   on the macOS version, so a Mac with another version may not match them.
// - SNAPSHOT_RECORD=1 rewrites every golden; SNAPSHOT_RECORD=routing,picker only those scenes'.
//   On CI, the "Record goldens" workflow does this and commits the result.
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
            try check(scene: name, "\(name)-\(dark ? "dark" : "light")", pixels)
        }
    }

    @Test func recordingTakesEveryScenesOrAList() {
        #expect(Self.records("routing", "1"))
        #expect(Self.records("routing", "general, routing"))
        #expect(!Self.records("routing", "routing-test"))
        #expect(!Self.records("routing", nil))
        #expect(!Self.records("routing", "0"))
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

    @Test func theRuleSheetPreviewCountsTheRecentLinksThePatternMatches() throws {
        let scene = try Scenes.make("rule-preview")
        defer { scene.remove() }
        let s = scene.settings
        let preview = try #require(s.draft?.preview(rules: s.editor.config.rules, recent: s.recentLinks))
        #expect(preview.recent?.matched == 3)
        #expect(preview.recent?.total == 5)
        #expect(preview.recent?.examples.first == "https://github.com/acme/api/pull/12")
    }

    @Test func aLinkPastedIntoANewDomainRuleKeepsItsHostAndSaysWhichRuleHidesIt() throws {
        let scene = try Scenes.make("rule-hidden")
        defer { scene.remove() }
        let s = scene.settings
        #expect(s.draft?.value == "docs.github.com")
        let preview = try #require(s.draft?.preview(rules: s.editor.config.rules, recent: s.recentLinks))
        #expect(preview.hiddenBy?.hasPrefix("Never matches: rule 1") == true)
    }

    @Test func movingAHiddenRuleAboveTheRuleThatHidesItMakesEveryRuleMatch() throws {
        let scene = try Scenes.make("routing")
        defer { scene.remove() }
        let s = scene.settings
        let hidden = Shadowing.unreachable(s.editor.config.rules)
        #expect(hidden == [Unreachable(rule: 2, by: 0)])
        let id = s.editor.config.rules[2].id
        s.moveAbove(id, to: try #require(Shadowing.fix(s.editor.config.rules, hidden[0])))
        #expect(s.editor.config.rules.first?.value == "docs.github.com")
        #expect(s.selected == id)
        #expect(Shadowing.unreachable(s.editor.config.rules).isEmpty)
    }

    @Test func aConflictKeepsTheEditsAndOffersBothChoices() throws {
        let scene = try Scenes.make("conflict")
        defer { scene.remove() }
        #expect(scene.settings.editor.conflict)
        #expect(scene.settings.editor.config.defaultProfile == "Profile 1")
    }

    /// Whether SNAPSHOT_RECORD asks for `scene`: `1` for every scene, or a comma-separated list.
    static func records(_ scene: String, _ setting: String?) -> Bool {
        guard let setting, !setting.isEmpty, setting != "0" else { return false }
        return setting == "1"
            || setting.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == scene }
    }

    private func check(scene: String, _ name: String, _ pixels: Pixels) throws {
        let environment = ProcessInfo.processInfo.environment
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        let png = try pixels.png()
        try png.write(to: Self.output.appendingPathComponent("\(name).png"))
        let golden = Self.goldens.appendingPathComponent("\(name).png")
        if Self.records(scene, environment["SNAPSHOT_RECORD"]) {
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
        Issue.record(
            """
            \(name) differs from its golden in \(changed) pixels. Diff: \(diffURL.path)
            If the change is intended, look at the render, then re-record it: on CI, run the "Record goldens" \
            workflow with scenes "\(scene)"; on the runner's macOS, SNAPSHOT_RECORD=\(scene) scripts/check SceneTests.
            """)
    }
}
