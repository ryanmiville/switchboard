import AppKit
import Carbon.HIToolbox
import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The Quick Switch shortcut and which destinations its panel shows.
struct QuickSwitchPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let e = model.editor
        let settings = e.config.picker ?? PickerSettings()
        let choices = QuickSwitch.choices(e.installed, settings)
        let all = choices.filter { $0.error == nil }.map(\.destination)
        Form {
            Section { PaneHeader(pane: .quickSwitch) }

            Section {
                LabeledContent {
                    ShortcutRecorder(chord: KeyChord(model.shortcut)) { model.record($0) }
                        .frame(width: 180)
                        .accessibilityIdentifier("shortcut")
                } label: {
                    RowLabel(
                        title: "Keyboard shortcut",
                        caption: "Press it over a browser to open the page in front."
                    ) {
                        SymbolTile(symbol: "command", color: .orange)
                    }
                }
                if let error = model.shortcutError { ErrorText(error) }
                LabeledContent {
                    Button("Open Quick Switch") { model.services.openQuickSwitch() }
                } label: {
                    RowLabel(title: "Try it now") { SymbolTile(symbol: "bolt.fill", color: .yellow) }
                }
            } header: {
                Text("Shortcut")
            }

            Section {
                if choices.isEmpty {
                    Text("No supported Chromium browsers were found.").foregroundStyle(.secondary)
                }
                ForEach(choices, id: \.destination) { choice in
                    Toggle(
                        isOn: Binding(
                            get: { settings.includes(choice.destination) },
                            set: { model.setShown(choice.destination, $0, all: all) })
                    ) {
                        HStack(spacing: 10) {
                            BrowserIcon(locator: choice.destination.browser, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(choice.profileName)
                                Text(choice.error ?? choice.browserName)
                                    .font(.caption)
                                    .foregroundStyle(choice.error == nil ? Color.secondary : Color.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button {
                                model.toggleFavorite(choice)
                            } label: {
                                Image(systemName: choice.favorite ? "star.fill" : "star")
                                    .foregroundStyle(choice.favorite ? Color.yellow : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(choice.favorite ? "Remove from favorites" : "Add to favorites")
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(choice.error != nil && !settings.includes(choice.destination))
                }
            } header: {
                Text("Destinations")
            } footer: {
                Text("Favorites come first in the panel, and ⌘1–⌘9 open them.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// A button that records the next key chord pressed while it is active.
struct ShortcutRecorder: NSViewRepresentable {
    let chord: KeyChord?
    let onRecord: (KeyChord) -> Void

    func makeNSView(context: Context) -> ShortcutButton {
        let button = ShortcutButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(ShortcutButton.beginRecording)
        return button
    }

    func updateNSView(_ button: ShortcutButton, context: Context) {
        button.chord = chord
        button.onRecord = onRecord
        if !button.recording { button.title = chord?.display ?? "Record Shortcut" }
    }
}

final class ShortcutButton: NSButton {
    var chord: KeyChord?
    var onRecord: (KeyChord) -> Void = { _ in }
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        guard !recording else { return }
        recording = true
        title = "Press shortcut… (Esc cancels)"
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            finish()
            return
        }
        let recorded = KeyChord(keyCode: UInt32(event.keyCode), modifiers: Self.carbon(event.modifierFlags))
        guard recorded.isValid, recorded.shortcut != nil else {
            title = "Use ⌃, ⌥, or ⌘ + a key"
            return
        }
        chord = recorded
        onRecord(recorded)
        finish()
    }

    override func resignFirstResponder() -> Bool {
        finish()
        return super.resignFirstResponder()
    }

    private func finish() {
        guard recording else { return }
        recording = false
        title = chord?.display ?? "Record Shortcut"
    }

    static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var bits: UInt32 = 0
        if flags.contains(.command) { bits |= KeyChord.command }
        if flags.contains(.shift) { bits |= KeyChord.shift }
        if flags.contains(.option) { bits |= KeyChord.option }
        if flags.contains(.control) { bits |= KeyChord.control }
        return bits
    }
}
