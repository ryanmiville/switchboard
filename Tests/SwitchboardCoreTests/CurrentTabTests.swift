import AppKit
import Testing

@testable import SwitchboardCore

func tabReply(_ url: String) -> NSAppleEventDescriptor {
    let reply = NSAppleEventDescriptor(
        eventClass: kCoreEventClass, eventID: kAEAnswer, targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    reply.setParam(NSAppleEventDescriptor(string: url), forKeyword: keyDirectObject)
    return reply
}

@MainActor
struct CurrentTabTests {
    @Test func focusedChromeInstanceWinsOverAutomationChromeWithTheSameBundleID() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = TabPickerModel(
            viewModel: ConfigViewModel(
                configURL: fixture.configURL, profileStore: BrowserProfiles(homeDirectory: fixture.root),
                browsers: [], autosaveDelay: 3600))
        model.browsers = { [] }
        // Two running Chrome instances share a bundle ID, but their active pages differ.
        // The OS's bundle-ID lookup happens to choose the automation instance.
        let personalChrome = CurrentTabSource(bundleIdentifier: "com.google.Chrome", processIdentifier: 42)
        let automationChrome = CurrentTabSource(bundleIdentifier: "com.google.Chrome", processIdentifier: 84)
        let pages: [pid_t: String] = [42: "https://www.youtube.com/", 84: "http://127.0.0.1:4431/test"]
        var targets: [pid_t] = []
        model.reader = CurrentTabReader(execute: { event in
            let address = try #require(event.attributeDescriptor(forKeyword: keyAddressAttr))
            let pid: pid_t
            if address.descriptorType == typeKernelProcessID {
                pid = address.data.withUnsafeBytes { $0.loadUnaligned(as: pid_t.self) }
            } else {
                #expect(address.descriptorType == typeApplicationBundleID)
                #expect(String(decoding: address.data, as: UTF8.self) == "com.google.Chrome")
                pid = automationChrome.processIdentifier
            }
            targets.append(pid)
            return tabReply(try #require(pages[pid]))
        })
        model.prepare(source: personalChrome)
        #expect(model.urlString == "https://www.youtube.com/")
        #expect(targets == [personalChrome.processIdentifier])
        model.prepare(source: automationChrome)
        #expect(model.urlString == "http://127.0.0.1:4431/test")
        #expect(targets == [personalChrome.processIdentifier, automationChrome.processIdentifier])
    }

    @Test(arguments: ["com.google.Chrome", "net.imput.helium", "company.thebrowser.Browser"])
    func queryReadsTheActiveTabOfTheCapturedProcess(_ bundleIdentifier: String) throws {
        let reader = CurrentTabReader(execute: { event in
            #expect(event.eventClass == kAECoreSuite)
            #expect(event.eventID == kAEGetData)
            let address = try #require(event.attributeDescriptor(forKeyword: keyAddressAttr))
            #expect(address.descriptorType == typeKernelProcessID)
            #expect(address.data.withUnsafeBytes { $0.loadUnaligned(as: pid_t.self) } == 42)
            let url = try #require(event.paramDescriptor(forKeyword: keyDirectObject))
            #expect(url.descriptorType == typeObjectSpecifier)
            #expect(url.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue == 0x5552_4C20)
            let tab = try #require(url.forKeyword(AEKeyword(keyAEContainer)))
            #expect(tab.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue == 0x6163_5461)
            let window = try #require(tab.forKeyword(AEKeyword(keyAEContainer)))
            let expectedClass =
                bundleIdentifier == "company.thebrowser.Browser" ? 0x5769_4E44 : DescType(cWindow)
            #expect(
                window.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue == expectedClass)
            // Absolute positions accept an integer index or an absolute ordinal,
            // not an enumerated descriptor (Chrome rejects that with -1700).
            let position = try #require(window.forKeyword(AEKeyword(keyAEKeyData)))
            #expect(position.descriptorType == typeSInt32)
            #expect(position.int32Value == 1)
            return tabReply("https://www.youtube.com/watch?v=example#part")
        })
        let url = try reader.read(
            source: CurrentTabSource(bundleIdentifier: bundleIdentifier, processIdentifier: 42))
        #expect(url.absoluteString == "https://www.youtube.com/watch?v=example#part")
    }

    @Test(arguments: [-1743, -1744])
    func permissionTransportErrorsKeepTheAutomationRecoveryAction(_ code: Int) {
        let reader = CurrentTabReader(execute: { _ in throw NSError(domain: NSOSStatusErrorDomain, code: code)
        })
        #expect(throws: CurrentTabError.automationDenied) {
            try reader.read(
                source: CurrentTabSource(bundleIdentifier: "com.google.Chrome", processIdentifier: 42))
        }
    }

    @Test(arguments: [Int32(-1728), Int32(-1719)])
    func missingWindowRepliesReportNoTab(_ code: Int32) {
        let reader = CurrentTabReader(execute: { _ in
            let reply = tabReply("")
            reply.setParam(NSAppleEventDescriptor(int32: code), forKeyword: keyErrorNumber)
            return reply
        })
        #expect(throws: CurrentTabError.noTab) {
            try reader.read(
                source: CurrentTabSource(bundleIdentifier: "com.google.Chrome", processIdentifier: 42))
        }
    }

    @Test func aClosedSourceProcessNeverFallsBackToAnotherChromeInstance() {
        var attempts = 0
        let reader = CurrentTabReader(execute: { event in
            attempts += 1
            #expect(
                event.attributeDescriptor(forKeyword: keyAddressAttr)?.descriptorType == typeKernelProcessID)
            throw NSError(domain: NSOSStatusErrorDomain, code: -600)
        })
        #expect(throws: CurrentTabError.unreadable) {
            try reader.read(
                source: CurrentTabSource(bundleIdentifier: "com.google.Chrome", processIdentifier: 42))
        }
        #expect(attempts == 1)
    }

    @Test(arguments: [pid_t(0), pid_t(-1)])
    func invalidProcessIDsAreRejectedBeforeSendingEvents(_ pid: pid_t) {
        let reader = CurrentTabReader(execute: { _ in
            Issue.record("Sent an event without a captured browser process")
            return tabReply("https://example.com")
        })
        #expect(throws: CurrentTabError.unsupportedBrowser) {
            try reader.read(
                source: CurrentTabSource(bundleIdentifier: "com.google.Chrome", processIdentifier: pid))
        }
    }
}
