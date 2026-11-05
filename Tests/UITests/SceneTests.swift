import AppKit
import Foundation
import SwitchboardCore
import SwitchboardEditor
import Testing

@testable import SwitchboardUI

// Every scene draws offscreen in light and dark. What scenes look like is checked by window shots
// of the real window (scripts/shoot) against the goldens in Tests/UITests/Goldens, on CI.
@MainActor
@Suite(.serialized)
struct SceneTests {
    @Test(arguments: Scenes.names)
    func everySceneDrawsInLightAndDark(scene name: String) async throws {
        for dark in [false, true] {
            let scene = try Scenes.make(name)
            defer { scene.remove() }
            // Throws when the view draws nothing.
            _ = try await Renderer.render(scene.view, size: scene.size, dark: dark)
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
        #expect(hidden.map { [$0.rule, $0.by] } == [[2, 0]])
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

    @Test func recentLinksListsHistoryNewestFirstWithTheRuleThatSentEach() throws {
        let scene = try Scenes.make("recent")
        defer { scene.remove() }
        let recent = scene.settings.editor.recent
        #expect(recent.first?.url == "https://github.com/acme/api/pull/12")
        #expect(recent.first?.reason == "Rule 1: Domain github.com")
        #expect(recent.count == 5)
    }

    @Test func addingARuleForARecentLinkStartsFromItsDomainAndQuickSwitchChoice() throws {
        let scene = try Scenes.make("recent-add-rule")
        defer { scene.remove() }
        let draft = try #require(scene.settings.draft)
        #expect(draft.isNew)
        #expect(draft.condition == .domain)
        #expect(draft.value == "figma.com")
        #expect(draft.profile == "Profile 3")
    }
}
