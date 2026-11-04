import Foundation
import Testing

@testable import SwitchboardCore

struct ConfigTests {
    static let currentApp = """
        {
          "browser" : "\\/Applications\\/Helium.app",
          "defaultProfile" : "Default",
          "history" : { "enabled" : false },
          "picker" : {
            "favorites" : [ { "browser" : "\\/Applications\\/Helium.app", "name" : "Ryan", "profile" : "Default" } ],
            "shortcut" : { "key" : "Space", "keyCode" : 49, "modifiers" : 6144 }
          },
          "routes" : [
            { "condition" : "domain", "profile" : "Profile 1", "value" : "github.com" },
            { "browser" : "\\/Applications\\/Google Chrome.app", "condition" : "contains", "profile" : "Work", "value" : "acme" }
          ]
        }
        """

    @Test func theCurrentAppsConfigLoadsWithItsRulesShortcutAndSettings() throws {
        let config = try Config.parse(Data(Self.currentApp.utf8))
        #expect(config.browser == "/Applications/Helium.app")
        #expect(config.rules.count == 2)
        #expect(config.rules[0].browser == nil)
        #expect(config.browser(of: config.rules[0]) == "/Applications/Helium.app")
        #expect(config.rules[1].profile == "Work")
        #expect(!config.historyEnabled)
        #expect(config.picker?.shortcut.text == "ctrl+alt+space")
    }

    @Test func aSavedConfigReadsBackTheSameAndOmitsWhatIsUnset() throws {
        let config = try Config.parse(Data(Self.currentApp.utf8))
        let text = String(decoding: config.encoded(), as: UTF8.self)
        #expect(text.contains("\"rules\""))
        #expect(!text.contains("routes"))
        #expect(!text.contains("\\/"), "slashes are written plainly")
        #expect(
            text.components(separatedBy: "\"browser\"").count - 1 == 3,
            "only the overriding rule saves a browser")
        #expect(text.hasSuffix("}\n"))
        let again = try Config.parse(Data(text.utf8))
        #expect(again.encoded() == config.encoded())
    }

    @Test func unknownKeysAreRefusedSoTyposSurface() {
        #expect {
            try Config.parse(Data(#"{"browser":"b","defaultProfile":"Default","rulez":[]}"#.utf8))
        } throws: { error in
            JSON.describe(error).contains("rulez")
        }
        #expect(throws: (any Error).self) {
            try Config.parse(
                Data(
                    #"{"browser":"b","defaultProfile":"D","rules":[{"condition":"domain","value":"a","profile":"P","brwser":"x"}]}"#
                        .utf8))
        }
    }

    @Test func rulesAndRoutesTogetherAreRefused() {
        #expect(throws: (any Error).self) {
            try Config.parse(Data(#"{"browser":"b","defaultProfile":"D","rules":[],"routes":[]}"#.utf8))
        }
    }

    @Test func omittedHistoryMeansEnabled() throws {
        let config = try Config.parse(Data(#"{"browser":"b","defaultProfile":"Default"}"#.utf8))
        #expect(config.historyEnabled)
        #expect(config.rules.isEmpty)
    }

    @Test func carbonShortcutsBecomeText() throws {
        let picker = try JSONDecoder().decode(
            PickerSettings.self, from: Data(#"{"shortcut":{"key":"←","keyCode":123,"modifiers":768}}"#.utf8))
        #expect(picker.shortcut.text == "shift+cmd+left")
        #expect(picker.includes(Destination(browser: "a", profile: "b")))
        #expect(!PickerSettings(destinations: []).includes(Destination(browser: "a", profile: "b")))
    }

    @Test func theEnvironmentIsReadOnlyForTheNamesSwitchboardUses() {
        let (home, env) = Env.parse([
            "HOME": "/Users/x", Env.applicationsVariable: "/a:/b", Env.configVariable: "/c.json",
            "OTHER": "1",
            "CODEX_HOME": "",
        ])
        #expect(home?.path == "/Users/x")
        #expect(env.applicationDirectories?.map(\.path) == ["/a", "/b"])
        #expect(env[Env.configVariable] == "/c.json")
        #expect(env["OTHER"] == nil)
        #expect(env["CODEX_HOME"] == nil)
        #expect(Env.parse(["HOME": ""]).home == nil)
        #expect(Home(path: "/Users/x").expand("~/a/b").path == "/Users/x/a/b")
        #expect(Home(path: "/Users/x").configFile.path == "/Users/x/.config/switchboard/config.json")
    }
}
