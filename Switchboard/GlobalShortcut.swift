import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var current: KeyboardShortcut?
    var onPress: () -> Void = {}

    func register(_ shortcut: KeyboardShortcut) throws {
        guard shortcut.isValid else { throw ShortcutError.invalid }
        if current?.keyCode == shortcut.keyCode, current?.modifiers == shortcut.modifiers { return }
        if eventHandler == nil {
            var event = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, context in
                    guard let event, let context else { return OSStatus(eventNotHandledErr) }
                    var identifier = EventHotKeyID()
                    let status = GetEventParameter(
                        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                    guard status == noErr, identifier.signature == 0x5357_4244, identifier.id == 1 else {
                        return OSStatus(eventNotHandledErr)
                    }
                    // Carbon dispatches application events on the main event loop.
                    MainActor.assumeIsolated {
                        Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().onPress()
                    }
                    return noErr
                }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            guard status == noErr else { throw ShortcutError.registration(status) }
        }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x5357_4244, id: 1),
            GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { throw ShortcutError.registration(status) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        current = shortcut
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        current = nil
    }

    isolated deinit { stop() }
}

enum ShortcutError: LocalizedError {
    case invalid
    case registration(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalid:
            "Choose a shortcut with Control, Option, or Command and a key."
        case .registration(let status):
            "The shortcut couldn’t be registered (\(status)). It may already be in use. Record another shortcut or use the menu-bar button."
        }
    }
}
