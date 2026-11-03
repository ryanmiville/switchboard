import Foundation
import SwitchboardCore

// The Quick Switch shortcut as config.json writes it (`ctrl+alt+space`), and as macOS registers
// it: a virtual key code and Carbon modifier bits. Kept here, without Carbon, so the mapping is
// tested on Linux; SwitchboardMac registers the result.

public struct KeyChord: Equatable, Sendable {
    /// The virtual key code (`kVK_Space` is 49).
    public var keyCode: UInt32
    /// Carbon modifier bits: `cmdKey` 0x100, `shiftKey` 0x200, `optionKey` 0x800, `controlKey` 0x1000.
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let command: UInt32 = 0x100
    public static let shift: UInt32 = 0x200
    public static let option: UInt32 = 0x800
    public static let control: UInt32 = 0x1000

    static let modifierNames: [(UInt32, String, String)] = [
        (control, "ctrl", "⌃"), (option, "alt", "⌥"), (shift, "shift", "⇧"), (command, "cmd", "⌘"),
    ]

    /// Key names as config.json writes them, with their virtual key codes and how menus show them.
    static let keys: [(name: String, code: UInt32, symbol: String)] = [
        ("a", 0, "A"), ("s", 1, "S"), ("d", 2, "D"), ("f", 3, "F"), ("h", 4, "H"), ("g", 5, "G"),
        ("z", 6, "Z"),
        ("x", 7, "X"), ("c", 8, "C"), ("v", 9, "V"), ("b", 11, "B"), ("q", 12, "Q"), ("w", 13, "W"),
        ("e", 14, "E"),
        ("r", 15, "R"), ("y", 16, "Y"), ("t", 17, "T"), ("1", 18, "1"), ("2", 19, "2"), ("3", 20, "3"),
        ("4", 21, "4"), ("6", 22, "6"), ("5", 23, "5"), ("=", 24, "="), ("9", 25, "9"), ("7", 26, "7"),
        ("-", 27, "-"), ("8", 28, "8"), ("0", 29, "0"), ("]", 30, "]"), ("o", 31, "O"), ("u", 32, "U"),
        ("[", 33, "["), ("i", 34, "I"), ("p", 35, "P"), ("return", 36, "↩"), ("l", 37, "L"), ("j", 38, "J"),
        ("'", 39, "'"), ("k", 40, "K"), (";", 41, ";"), ("\\", 42, "\\"), (",", 43, ","), ("/", 44, "/"),
        ("n", 45, "N"), ("m", 46, "M"), (".", 47, "."), ("tab", 48, "⇥"), ("space", 49, "Space"),
        ("`", 50, "`"),
        ("backspace", 51, "⌫"), ("escape", 53, "⎋"), ("f5", 96, "F5"), ("f6", 97, "F6"), ("f7", 98, "F7"),
        ("f3", 99, "F3"), ("f8", 100, "F8"), ("f9", 101, "F9"), ("f11", 103, "F11"), ("f10", 109, "F10"),
        ("f12", 111, "F12"), ("f4", 118, "F4"), ("f2", 120, "F2"), ("f1", 122, "F1"), ("left", 123, "←"),
        ("right", 124, "→"), ("down", 125, "↓"), ("up", 126, "↑"),
    ]

    /// A global shortcut needs Control, Option or Command; Shift alone would take a typed key.
    public var isValid: Bool { modifiers & (Self.command | Self.option | Self.control) != 0 }

    /// Parses `ctrl+alt+space`. Modifier names: ctrl/control, alt/option/opt, shift, cmd/command/super.
    public init?(_ shortcut: Shortcut) {
        let parts = shortcut.text.lowercased().split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let keyName = parts.last, let key = Self.keys.first(where: { $0.name == keyName }) else {
            return nil
        }
        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "ctrl", "control": modifiers |= Self.control
            case "alt", "option", "opt": modifiers |= Self.option
            case "shift": modifiers |= Self.shift
            case "cmd", "command", "super", "meta": modifiers |= Self.command
            default: return nil
            }
        }
        self.init(keyCode: key.code, modifiers: modifiers)
    }

    /// The config text: `ctrl+alt+space`. `nil` for a key with no name.
    public var shortcut: Shortcut? {
        guard let key = Self.keys.first(where: { $0.code == keyCode }) else { return nil }
        let names = Self.modifierNames.filter { modifiers & $0.0 != 0 }.map(\.1)
        return Shortcut((names + [key.name]).joined(separator: "+"))
    }

    /// How menus show it: `⌃⌥Space`.
    public var display: String {
        let key = Self.keys.first { $0.code == keyCode }?.symbol ?? "Key \(keyCode)"
        return Self.modifierNames.filter { modifiers & $0.0 != 0 }.map(\.2).joined() + key
    }
}
