import AppKit

struct CurrentTabSource: Equatable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
}

struct CurrentTabReader {
    var execute: (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor = { event in
        try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 3)
    }

    func read(source: CurrentTabSource?) throws -> URL {
        guard let source, source.processIdentifier > 0,
            BrowserProfiles.dataDirectories[source.bundleIdentifier] != nil
        else {
            throw CurrentTabError.unsupportedBrowser
        }
        let reply: NSAppleEventDescriptor
        do {
            reply = try execute(Self.readEvent(source: source))
        } catch let error as CurrentTabError {
            throw error
        } catch {
            throw Self.failure(code: (error as NSError).code)
        }
        if let code = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, code != 0 {
            throw Self.failure(code: Int(code))
        }
        let value = reply.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? ""
        guard !value.isEmpty else { throw CurrentTabError.noTab }
        guard let url = URL(string: value), Router.isWebURL(url) else { throw CurrentTabError.nonWebURL }
        return url
    }

    private static func failure(code: Int) -> CurrentTabError {
        switch code {
        case -1743, -1744: .automationDenied
        case -1728, -1719: .noTab
        default: .unreadable
        }
    }

    private static func readEvent(source: CurrentTabSource) -> NSAppleEventDescriptor {
        // Arc uses WiND for its window class; Chromium browsers use cwin.
        let isArc = ["company.thebrowser.Browser", "com.keksbay.Arc"].contains(source.bundleIdentifier)
        // Windows are ordered front to back. An integer index avoids encoding an
        // absolute ordinal as an enum, which Chrome rejects with errAECoercionFail.
        let window = object(
            desiredClass: isArc ? 0x5769_4E44 : DescType(cWindow),
            form: OSType(formAbsolutePosition), key: NSAppleEventDescriptor(int32: 1))
        let tab = object(
            desiredClass: typeProperty, form: OSType(formPropertyID),
            key: NSAppleEventDescriptor(typeCode: 0x6163_5461), container: window)  // acTa
        let url = object(
            desiredClass: typeProperty, form: OSType(formPropertyID),
            key: NSAppleEventDescriptor(typeCode: 0x5552_4C20), container: tab)  // URL[space]
        let event = NSAppleEventDescriptor(
            eventClass: kAECoreSuite, eventID: kAEGetData,
            // Automation browsers can share the same bundle ID as the user's browser.
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: source.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(url, forKeyword: keyDirectObject)
        return event
    }

    private static func object(
        desiredClass: DescType, form: OSType, key: NSAppleEventDescriptor,
        container: NSAppleEventDescriptor = .null()
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(
            NSAppleEventDescriptor(typeCode: desiredClass), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: typeObjectSpecifier)!
    }
}

enum CurrentTabError: LocalizedError {
    case unsupportedBrowser, automationDenied, noTab, nonWebURL, unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedBrowser:
            "Focus a supported browser and try the shortcut again, or paste a link below."
        case .automationDenied:
            "Switchboard couldn’t get permission to read this browser. In System Settings → Privacy & Security → Automation, expand Switchboard and enable the browser. If Switchboard is missing, reopen it and try the shortcut from your browser to request access. You can also paste the link below."
        case .noTab:
            "The browser has no open tab. Open a web page and try again, or paste a link below."
        case .nonWebURL:
            "This tab isn’t an HTTP or HTTPS page. Paste a complete web link below."
        case .unreadable:
            "The current tab couldn’t be read. Try again from the browser, or copy its address and paste it below."
        }
    }
}
