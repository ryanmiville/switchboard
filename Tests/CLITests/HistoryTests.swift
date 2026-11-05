import Testing

struct HistoryTests {
    @Test func historyListsNewestFirstWithURLsRedactedUnlessAsked() throws {
        let f = try Fixture()
        try f.rules([])
        try f.history([
            entry("11110000", "https://a.com/old"), entry("22220000", "https://u:p@b.com/new?code=1#x"),
        ])
        let out = try f.json(["history"]).ok().json()
        #expect(out["entries"][0]["id"] == "22220000")
        #expect(out["entries"][0]["url"] == "https://…@b.com/new?…#…")
        let full = try f.json(["history", "--full-urls", "--limit", "1"]).ok().json()
        #expect(full["entries"].array.count == 1)
        #expect(full["entries"][0]["url"] == "https://u:p@b.com/new?code=1#x")
        let text = try f.run(["history"]).ok().stdout
        #expect(text.contains("22220000"), "\(text)")
        #expect(!text.contains("code=1"), "\(text)")
    }

    @Test func explainAndRouteTakeTheLastEntryOrAnIDFragment() throws {
        let f = try Fixture()
        try f.rules([])
        try f.history([entry("abcd1234", "https://a.com/x?t=1"), entry("ffff9999", "https://b.com/")])
        let last = try f.json(["explain", "--last"]).ok().json()
        #expect(last["url"] == "https://b.com/")
        #expect(last["history"]["id"] == "ffff9999")
        let bySuffix = try f.json(["explain", "--history", "1234"]).ok().json()
        #expect(bySuffix["url"] == "https://a.com/x?…")
        _ = try f.json(["route", "--history", "abcd", "--profile", "Work"]).ok()
        #expect(try f.readConfig()["rules"][0]["value"] == "a.com")
    }

    @Test func anUnknownHistoryIDExits3WithRecentEntries() throws {
        let f = try Fixture()
        try f.rules([])
        try f.history([entry("abcd1234", "https://a.com/")])
        let run = try f.json(["explain", "--history", "zzzz"])
        #expect(run.status == 3)
        #expect(try run.code() == "history_entry_not_found")
        #expect(try run.json()["error"]["candidates"][0]["id"] == "abcd1234")
    }

    @Test func turningHistoryOffMakesHistoryCommandsRefuseButClearStillWorks() throws {
        let f = try Fixture()
        try f.rules([])
        try f.history([entry("abcd1234", "https://a.com/")])
        _ = try f.json(["history", "off"]).ok()
        #expect(try f.readConfig()["history"] == ["enabled": false])
        let run = try f.json(["explain", "--last"])
        #expect(run.status == 1)
        #expect(try run.code() == "history_disabled")
        #expect(try f.json(["history", "clear"]).ok().json()["entries"] == 1)
        _ = try f.json(["history", "on"]).ok()
        #expect(try !f.readConfig().has("history"), "on is the default, so the key goes away")
    }
}

struct PickerTests {
    @Test func pickerSettingsAreChangedThroughTheCLI() throws {
        let f = try Fixture()
        try f.rules([])
        _ = try f.json(["picker", "shortcut", "Ctrl+Shift+K"]).ok()
        _ = try f.json(["picker", "destination", "--browser", "Helium", "--profile", "Work", "--hide"]).ok()
        let picker = try f.readConfig()["picker"]
        #expect(picker["shortcut"] == "ctrl+shift+k")
        #expect(picker["destinations"].array.count == 5, "every destination but Helium · Work")
        _ = try f.json(["picker", "show-all"]).ok()
        #expect(try !f.readConfig()["picker"].has("destinations"))
        #expect(try f.json(["picker", "shortcut", "space"]).status == 2)
        #expect(
            try f.json(["picker", "favorite", "--browser", "Chrome", "--profile", "Profile 3"]).status == 2)
    }

    @Test func favoritesInAnOlderConfigAreAcceptedAndDroppedByTheNextPickerChange() throws {
        let f = try Fixture()
        try f.config([
            "browser": .string(f.helium), "defaultProfile": "Default", "rules": [],
            "picker": [
                "shortcut": "ctrl+alt+space",
                "favorites": [["browser": .string(f.helium), "profile": "Default", "name": "Ryan"]],
            ],
        ])
        _ = try f.json(["picker", "show"]).ok()
        #expect(try f.readConfig()["picker"].has("favorites"), "reading leaves the file alone")
        _ = try f.json(["picker", "shortcut", "ctrl+shift+k"]).ok()
        let picker = try f.readConfig()["picker"]
        #expect(!picker.has("favorites"))
        #expect(picker["shortcut"] == "ctrl+shift+k")
    }

    @Test func onlyThenAddingSetsAnExactListOfDestinations() throws {
        let f = try Fixture()
        try f.rules([])
        _ = try f.json(["picker", "destination", "--browser", "Helium", "--profile", "Default", "--only"])
            .ok()
        _ = try f.json(["picker", "destination", "--browser", "Chrome", "--profile", "Profile 1"]).ok()
        #expect(
            try f.readConfig()["picker"]["destinations"] == [
                ["browser": .string(f.helium), "profile": "Default"],
                ["browser": .string(f.chrome), "profile": "Profile 1"],
            ])
        let shown = try f.json(["picker", "show"]).ok().json()
        #expect(shown["picker"]["destinations"].array.count == 2)
    }
}
