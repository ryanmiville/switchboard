import AppKit
import SwitchboardCore
import SwitchboardEditor

/// The app in front when the picker was summoned.
public struct Frontmost: Equatable, Sendable {
    /// Its bundle identifier.
    public var id: String
    public var pid: pid_t
}

/// The focused browser's current tab, for Quick Switch, read over Apple Events. macOS asks the
/// person to allow Automation for each browser the first time.
public enum CurrentTab {
    /// The app in front now. Call it before showing any window.
    @MainActor
    public static func frontmost() -> Frontmost? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return Frontmost(id: id, pid: app.processIdentifier)
    }

    /// The link in `app`'s frontmost window's active tab, exactly as the browser reports it, and
    /// the window's title, which names the profile. Can block for a few seconds, so call it off the
    /// main thread.
    public static func read(_ app: Frontmost) -> Result<BrowserTab, TabError> {
        guard app.pid > 0, Browsers.bundles.contains(where: { $0.id == app.id }) else {
            return .failure(.unsupportedBrowser)
        }
        let link: String
        switch get(tabURL(app), from: app) {
        case .failure(let error): return .failure(error)
        case .success(let value): link = value
        }
        guard !link.isEmpty else { return .failure(.noTab) }
        guard Link.isWeb(link) else { return .failure(.notWeb) }
        // The title only lets the panel leave out the profile being switched from, so it's best effort.
        let title = try? get(windowName(app), from: app).get()
        return .success(BrowserTab(link: link, windowTitle: title))
    }

    /// Asks `app` for the string at `specifier`.
    private static func get(_ specifier: NSAppleEventDescriptor, from app: Frontmost) -> Result<
        String, TabError
    > {
        let event = NSAppleEventDescriptor(
            eventClass: kAECoreSuite, eventID: kAEGetData,
            // Automation browsers can share the bundle identifier of the person's own browser.
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(specifier, forKeyword: keyDirectObject)
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 3)
        } catch {
            return .failure(failure((error as NSError).code))
        }
        if let code = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, code != 0 {
            return .failure(failure(Int(code)))
        }
        return .success(reply.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? "")
    }

    /// Brings `browser` forward after opening a link in it.
    @MainActor
    public static func activate(_ browser: BrowserInfo) {
        NSRunningApplication.runningApplications(withBundleIdentifier: browser.id).first?.activate(options: []
        )
    }

    /// Opens System Settings → Privacy & Security → Automation.
    @MainActor
    public static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        {
            NSWorkspace.shared.open(url)
        }
    }

    private static func failure(_ code: Int) -> TabError {
        switch code {
        case -1743, -1744: .automationDenied
        case -1728, -1719: .noTab
        default: .unreadable
        }
    }

    /// The frontmost window. Windows are ordered front to back. An integer index avoids encoding an
    /// absolute ordinal as an enum, which Chrome rejects with errAECoercionFail.
    private static func frontWindow(_ app: Frontmost) -> NSAppleEventDescriptor {
        // Arc uses WiND for its window class; Chromium browsers use cwin.
        let isArc = ["company.thebrowser.Browser", "com.keksbay.Arc"].contains(app.id)
        return object(
            isArc ? 0x5769_4E44 : DescType(cWindow), form: OSType(formAbsolutePosition),
            key: NSAppleEventDescriptor(int32: 1))
    }

    /// The URL of the front window's active tab.
    private static func tabURL(_ app: Frontmost) -> NSAppleEventDescriptor {
        let tab = object(
            typeProperty, form: OSType(formPropertyID), key: NSAppleEventDescriptor(typeCode: 0x6163_5461),
            container: frontWindow(app))  // acTa
        return object(
            typeProperty, form: OSType(formPropertyID), key: NSAppleEventDescriptor(typeCode: 0x5552_4C20),
            container: tab)  // URL[space]
    }

    /// The front window's title.
    private static func windowName(_ app: Frontmost) -> NSAppleEventDescriptor {
        object(
            typeProperty, form: OSType(formPropertyID), key: NSAppleEventDescriptor(typeCode: 0x706E_616D),
            container: frontWindow(app))  // pnam
    }

    private static func object(
        _ desiredClass: DescType, form: OSType, key: NSAppleEventDescriptor,
        container: NSAppleEventDescriptor = .null()
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(
            NSAppleEventDescriptor(typeCode: desiredClass), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: typeObjectSpecifier) ?? record
    }
}

/// Brings this app forward, as opening Settings from the menu-bar item does.
@MainActor
public func bringToFront() {
    NSApplication.shared.activate(ignoringOtherApps: true)
}
