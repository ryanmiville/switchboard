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

struct Route: Codable, Identifiable, Equatable {
    var id: UUID
    var condition: Condition
    var value: String
    var profile: String

    init(id: UUID = UUID(), condition: Condition = .contains, value: String = "", profile: String = "Default")
    {
        self.id = id
        self.condition = condition
        self.value = value
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case condition, value, profile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.condition = try container.decode(Condition.self, forKey: .condition)
        self.value = try container.decode(String.self, forKey: .value)
        self.profile = try container.decode(String.self, forKey: .profile)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(condition, forKey: .condition)
        try container.encode(value, forKey: .value)
        try container.encode(profile, forKey: .profile)
    }
}

struct Config: Codable, Equatable {
    var browser: String
    var defaultProfile: String
    var routes: [Route]

    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/switchboard/config.json")

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

    func save(to path: URL = Self.configPath) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)

        // Ensure directory exists
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try data.write(to: path, options: .atomic)
    }
}
