import Foundation

struct Profile: Identifiable, Hashable {
    let name: String  // Display name (e.g., "Ryan", "H3")
    let directory: String  // Directory identifier (e.g., "Default", "Profile 1")

    var id: String { directory }
}

enum Condition: String, Codable, CaseIterable {
    case contains
    case exact
    case domain

    var label: String {
        switch self {
        case .contains: "Contains"
        case .exact: "Exact"
        case .domain: "Domain"
        }
    }
}

struct Destination: Codable, Equatable, Hashable {
    let browser: String
    let profile: String
}

struct Route: Codable, Identifiable, Equatable {
    var id: UUID
    var condition: Condition
    var value: String
    var profile: String
    var browser: String?

    init(
        id: UUID = UUID(), condition: Condition = .contains, value: String = "", profile: String = "Default",
        browser: String? = nil
    ) {
        self.id = id
        self.condition = condition
        self.value = value
        self.profile = profile
        self.browser = browser
    }

    enum CodingKeys: String, CodingKey {
        case condition, value, profile, browser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.condition = try container.decode(Condition.self, forKey: .condition)
        self.value = try container.decode(String.self, forKey: .value)
        self.profile = try container.decode(String.self, forKey: .profile)
        self.browser = try container.decodeIfPresent(String.self, forKey: .browser)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(condition, forKey: .condition)
        try container.encode(value, forKey: .value)
        try container.encode(profile, forKey: .profile)
        try container.encodeIfPresent(browser, forKey: .browser)
    }
}

// Omitted in older files: history is recorded unless a file turns it off.
struct HistorySettings: Codable, Equatable {
    var enabled = true

    init(enabled: Bool = true) {
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct Config: Codable, Equatable {
    var browser: String
    var defaultProfile: String
    var routes: [Route]
    var picker: PickerSettings? = nil
    var history: HistorySettings? = nil

    var browserPaths: Set<String> { Set([browser] + routes.compactMap(\.browser)) }
    var historyEnabled: Bool { history?.enabled ?? true }

    static let configPath = path(home: FileManager.default.homeDirectoryForCurrentUser)

    static func path(home: URL) -> URL {
        home.appendingPathComponent(".config/switchboard/config.json")
    }

    static func load(from path: URL = configPath) throws -> Config {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    static let defaults = Config(browser: "/Applications/Helium.app", defaultProfile: "Default", routes: [])

    static func loadOrDefault(from path: URL = configPath) throws -> Config {
        do {
            return try load(from: path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return defaults
        }
    }

    // The app and the CLI share these settings so a CLI edit doesn't reformat the file.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func save(to path: URL = Self.configPath) throws {
        let data = try encoded()

        // Ensure directory exists
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try data.write(to: path, options: .atomic)
    }
}
