import Foundation

enum Condition: String, Codable {
    case contains
    case exact
}

struct Route: Codable {
    let condition: Condition
    let value: String
    let profile: String
}

struct Config: Codable {
    let browser: String
    let defaultProfile: String
    let routes: [Route]
    
    static func load() throws -> Config {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/switchboard/config.json")
        
        let data = try Data(contentsOf: configPath)
        return try JSONDecoder().decode(Config.self, from: data)
    }
}
