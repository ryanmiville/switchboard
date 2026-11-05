import Foundation

// The Quick Switch picker's settings in config.json.

/// A global shortcut as text, such as `ctrl+alt+space` or `cmd+shift+l`.
public struct Shortcut: Codable, Hashable, Sendable {
    public var text: String

    public init(_ text: String) { self.text = text }

    public static let standard = Shortcut("ctrl+alt+space")

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }

    /// A string, or the current app's `{keyCode, modifiers, key}` with Carbon modifier bits.
    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.text = text
            return
        }
        try decoder.refuseUnknownKeys(["key", "keyCode", "modifiers"])
        let c = try decoder.container(keyedBy: AnyKey.self)
        let modifiers = try c.decode(UInt32.self, forKey: AnyKey("modifiers"))
        let key = try c.decode(String.self, forKey: AnyKey("key"))
        _ = try c.decode(UInt32.self, forKey: AnyKey("keyCode"))
        let names: [(UInt32, String)] = [
            (0x1000, "ctrl"), (0x0800, "alt"), (0x0200, "shift"), (0x0100, "cmd"),
        ]
        let parts = names.filter { modifiers & $0.0 != 0 }.map(\.1)
        let keyName =
            switch key {
            case "←": "left"
            case "→": "right"
            case "↑": "up"
            case "↓": "down"
            default: key.lowercased()
            }
        text = (parts + [keyName]).joined(separator: "+")
    }
}

public struct PickerSettings: Codable, Equatable, Sendable {
    public var shortcut: Shortcut
    /// The destinations the picker shows. `nil` shows everything; empty shows nothing.
    public var destinations: [Destination]?

    public init(
        shortcut: Shortcut = .standard, destinations: [Destination]? = nil
    ) {
        self.shortcut = shortcut
        self.destinations = destinations
    }

    enum CodingKeys: String, CodingKey { case shortcut, destinations }

    /// `favorites`, from before the picker dropped them, is accepted and left out of the next save.
    public init(from decoder: Decoder) throws {
        try decoder.refuseUnknownKeys(["destinations", "favorites", "shortcut"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? .standard
        destinations = try c.decodeIfPresent([Destination].self, forKey: .destinations)
    }

    public func includes(_ destination: Destination) -> Bool {
        destinations.map { $0.contains(destination) } ?? true
    }
}
