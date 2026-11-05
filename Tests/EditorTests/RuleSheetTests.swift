import Foundation
import SwitchboardCore
import SwitchboardFixtures
import Testing

@testable import SwitchboardEditor

struct RuleSheetTests {
    @Test func aWholeLinkPastedIntoADomainRuleBecomesItsHost() {
        var draft = Draft.newRule()
        draft.enterPattern("https://me@Docs.GitHub.com:443/acme/api?tab=1")
        #expect(draft.value == "docs.github.com")
    }

    @Test func aLinkTypedOneCharacterAtATimeIntoADomainRuleStaysAsTyped() {
        var draft = Draft.newRule()
        for character in "https://github.com" { draft.enterPattern(draft.value + String(character)) }
        #expect(draft.value == "https://github.com")
    }

    @Test func aLinkPastedIntoAContainsOrExactRuleStaysWhole() {
        for condition in [Condition.contains, .exact] {
            var draft = Draft.newRule()
            draft.selectCondition(condition)
            draft.enterPattern("https://github.com/acme")
            #expect(draft.value == "https://github.com/acme")
        }
    }

    @Test func switchingToDomainWithAWholeLinkKeepsItsHost() {
        var draft = Draft.newRule()
        draft.selectCondition(.exact)
        draft.enterPattern("https://example.com/login")
        draft.selectCondition(.domain)
        #expect(draft.value == "example.com")
    }

    @Test func pastingTextThatIsntAWebLinkIntoADomainRuleKeepsIt() {
        var draft = Draft.newRule()
        draft.enterPattern("github.com/acme")
        #expect(draft.value == "github.com/acme")
    }

    @Test func anEditCountsOnlyTheCharactersItPutIn() {
        #expect(Draft.inserted(from: "", to: "a") == 1)
        #expect(Draft.inserted(from: "github.com", to: "github.comm") == 1)
        #expect(Draft.inserted(from: "github.com", to: "gitlab.com") == 2)
        #expect(Draft.inserted(from: "abc", to: "ab") == 0)
        #expect(Draft.inserted(from: "aa", to: "aaa") == 1)
    }

    @Test func thePreviewIsEmptyUntilThereIsAPattern() {
        var draft = Draft.newRule()
        draft.value = "  "
        #expect(draft.preview(rules: [], recent: []) == nil)
    }

    @Test func aDomainPreviewSaysSubdomainsMatchAndLookalikesDont() throws {
        var draft = Draft.newRule()
        draft.value = "github.com"
        let preview = try #require(draft.preview(rules: [], recent: []))
        #expect(preview.summary?.contains("www.github.com") == true)
        #expect(preview.summary?.contains("Not mygithub.com") == true)
        #expect(preview.problem == nil)
        #expect(preview.recent == nil, "no history, no count")
    }

    @Test func aDomainPreviewWithAPathSaysWhyItCantBeSaved() throws {
        var draft = Draft.newRule()
        draft.value = "github.com/acme"
        #expect(
            try #require(draft.preview(rules: [], recent: [])).problem?.contains("isn’t a domain") == true)
    }

    @Test func anExactPatternThatIsntALinkCanNeverMatch() throws {
        var draft = Draft.newRule()
        draft.selectCondition(.exact)
        draft.value = "example.com/login"
        #expect(try #require(draft.preview(rules: [], recent: [])).problem?.contains("complete link") == true)
    }

    @Test func thePreviewCountsTheRecentLinksThePatternMatchesWithRedactedExamples() throws {
        var draft = Draft.newRule()
        draft.value = "github.com"
        let recent = [
            "https://github.com/acme/api?token=secret", "https://example.com", "https://docs.github.com/x",
            "https://mygithub.com", "https://gist.github.com", "https://github.com/b",
        ]
        let preview = try #require(draft.preview(rules: [], recent: recent))
        #expect(preview.recent?.matched == 4)
        #expect(preview.recent?.total == 6)
        #expect(
            preview.recent?.examples == [
                "https://github.com/acme/api?…", "https://docs.github.com/x", "https://gist.github.com",
            ])
    }

    @Test func aNewRuleHiddenByAnExistingOneSaysWhichRule() throws {
        var draft = Draft.newRule()
        draft.value = "docs.github.com"
        let rules = [Rule(.contains, "acme", profile: "P"), Rule(.domain, "github.com", profile: "P")]
        let preview = try #require(draft.preview(rules: rules, recent: []))
        #expect(preview.hiddenBy?.hasPrefix("Never matches: rule 2 (Domain github.com)") == true)
    }

    @Test func anEditedRuleIsOnlyHiddenByRulesAboveIt() throws {
        let rules = [
            Rule(.domain, "docs.github.com", profile: "P"), Rule(.domain, "github.com", profile: "P"),
        ]
        var draft = Draft.editing(rules[0])
        draft.value = "api.github.com"
        #expect(try #require(draft.preview(rules: rules, recent: [])).hiddenBy == nil)
    }

    @Test func recentLinksComeFromHistoryNewestFirstEachOnce() throws {
        let scene = try SceneHome()
        defer { scene.remove() }
        let config = try scene.temporary.configStore.load().config
        for (i, link) in ["https://a.com", "https://b.com", "https://a.com"].enumerated() {
            _ = History.record(
                link, destination: config.defaultDestination, origin: .default, config: config, error: nil,
                now: Timestamp(Int64(i)), store: scene.temporary.historyStore, browsers: scene.browsers)
        }
        #expect(editor(scene).recentLinks() == ["https://a.com", "https://b.com"])
    }
}
