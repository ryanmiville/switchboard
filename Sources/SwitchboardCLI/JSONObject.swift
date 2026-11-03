import Foundation

// The CLI's JSON reports, built field by field like the Rust CLI's `serde_json::json!`. A field set
// with `set` is written even when it is nil (as `null`); `setIfPresent` leaves a nil field out.

struct JSONObject: Encodable {
    private var fields: [(String, any Encodable)] = []

    init() {}

    /// Writes `value`, as `null` when it is nil.
    mutating func set(_ key: String, _ value: some Encodable) {
        fields.removeAll { $0.0 == key }
        fields.append((key, value))
    }

    /// Writes `value` only when it isn't nil.
    mutating func setIfPresent<T: Encodable>(_ key: String, _ value: T?) {
        guard let value else { return }
        set(key, value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in fields { try container.encode(value, forKey: Key(key)) }
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

enum JSONText {
    /// Indented for people at a terminal, one line for programs reading a pipe. Keys are sorted, as
    /// the Rust CLI's are.
    static func encode(_ value: some Encodable, terminal: Bool) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting =
            terminal
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            return #"{"error":{"code":"failed","message":"Output couldn't be encoded."}}"# + "\n"
        }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
