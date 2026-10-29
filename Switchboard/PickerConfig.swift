import Foundation

// Picker settings stored in config.json. Kept free of AppKit and Carbon so the
// configuration types build on their own.

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    // kVK_Space with controlKey | optionKey; PickerTests checks these against Carbon.
    static let `default` = KeyboardShortcut(keyCode: 0x31, modifiers: 0x1000 | 0x0800, key: "Space")
}

struct PickerFavorite: Codable, Equatable, Identifiable {
    var browser: String
    var profile: String
    var name: String

    var destination: Destination { Destination(browser: browser, profile: profile) }
    var id: Destination { destination }
}

struct PickerSettings: Codable, Equatable {
    var shortcut: KeyboardShortcut = .default
    var favorites: [PickerFavorite] = []
    // Omitted in older files: show everything. An empty array deliberately shows nothing.
    var destinations: [Destination]?

    func includes(_ destination: Destination) -> Bool {
        destinations?.contains(destination) ?? true
    }
}
