import Foundation
import SwitchboardCore

/// The state scenes and app tests start from: a temporary home with fixture Helium and Chrome
/// installs, a config with four rules (one of them hidden by another).
/// Never the real home.
public struct SceneHome: Sendable {
    public let temporary: TemporaryHome
    public let helium: String
    public let chrome: String

    public var home: Home { temporary.home }
    public var browsers: Browsers { temporary.browsers }

    public init() throws {
        temporary = try TemporaryHome()
        helium = try temporary.installBrowser(
            .helium, name: "Helium", profiles: [("Default", "Ryan"), ("Profile 1", "Work")])
        chrome = try temporary.installBrowser(
            .chrome, name: "Google Chrome",
            profiles: [("Default", "Chrome Ryan"), ("Profile 2", "Work"), ("Profile 3", "Side project")])
        let config = Config(
            browser: helium, defaultProfile: "Default",
            rules: [
                Rule(.domain, "github.com", profile: "Profile 1"),
                Rule(.contains, "acme", profile: "Profile 2", browser: chrome),
                Rule(.domain, "docs.github.com", profile: "Default"),
                Rule(.exact, "https://example.com/login", profile: "Profile 3", browser: chrome),
            ])
        try temporary.configStore.save(config, expecting: nil)
    }

    public func remove() { temporary.remove() }
}
