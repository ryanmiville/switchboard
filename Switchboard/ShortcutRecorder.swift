import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut
    let onRecord: (KeyboardShortcut) -> Void
    let onRecordingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> ShortcutButton {
        let button = ShortcutButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(ShortcutButton.beginRecording)
        return button
    }

    func updateNSView(_ button: ShortcutButton, context: Context) {
        button.shortcut = shortcut
        button.onRecord = onRecord
        button.onRecordingChanged = onRecordingChanged
        button.isEnabled = isEnabled
        if !button.recording { button.title = shortcut.label }
    }
}

final class ShortcutButton: NSButton {
    var shortcut = KeyboardShortcut.default
    var onRecord: (KeyboardShortcut) -> Void = { _ in }
    var onRecordingChanged: (Bool) -> Void = { _ in }
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowResignedKey), name: NSWindow.didResignKeyNotification,
                object: window)
        } else {
            finishRecording()
        }
    }

    @objc private func windowResignedKey() { finishRecording() }

    @objc func beginRecording() {
        guard !recording else { return }
        recording = true
        title = "Press shortcut… (Esc cancels)"
        onRecordingChanged(true)
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
            finishRecording()
        } else if let value = KeyboardShortcut.recording(event) {
            onRecord(value)
            shortcut = value
            finishRecording()
        } else {
            title = "Use ⌃, ⌥, or ⌘ + a key"
        }
    }

    private func finishRecording() {
        guard recording else { return }
        recording = false
        title = shortcut.label
        onRecordingChanged(false)
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }
}
