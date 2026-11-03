import Carbon.HIToolbox
import Foundation
import SwitchboardEditor

/// The Quick Switch shortcut, registered with Carbon's hot-key API (the one global-shortcut API
/// that needs no Accessibility permission). One shortcut at a time; registering a new one replaces
/// the old only once the new one is accepted, so a refused chord leaves the old one working.
@MainActor
public final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var current: KeyChord?
    public var onPress: () -> Void = {}

    public init() {}

    public func register(_ chord: KeyChord) throws(ShortcutError) {
        guard chord.isValid else { throw .invalid }
        if current == chord { return }
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
                        nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                    guard status == noErr, identifier.signature == 0x5357_4E58, identifier.id == 1 else {
                        return OSStatus(eventNotHandledErr)
                    }
                    // Carbon dispatches application events on the main event loop.
                    MainActor.assumeIsolated {
                        Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().onPress()
                    }
                    return noErr
                }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            guard status == noErr else { throw .registration(status) }
        }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            chord.keyCode, chord.modifiers, EventHotKeyID(signature: 0x5357_4E58, id: 1),
            GetApplicationEventTarget(),
            0, &replacement)
        guard status == noErr else { throw .registration(status) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        current = chord
    }

    public func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        current = nil
    }
}

public enum ShortcutError: Error, CustomStringConvertible {
    case invalid
    case registration(OSStatus)

    public var description: String {
        switch self {
        case .invalid: "Choose a shortcut with Control, Option, or Command and a key."
        case .registration(let status):
            "The shortcut couldn’t be registered (\(status)). It may already be in use. Record another shortcut or use the menu-bar item."
        }
    }
}
