import Testing

@testable import SwitchboardCore

struct RoutingSessionTests {
    @Test func normalLaunchStaysResidentWithoutOpeningSettings() {
        var session = RoutingSession()
        #expect(session.hidesEditor)
        session.finishLaunching()
        #expect(session.keepsRunning)
        #expect(!session.keepsEditorOpen)
        #expect(session.hidesEditor)
        let ticket = session.receiveURL()
        #expect(!session.shouldTerminate(after: ticket))
    }

    @Test func loginLaunchStaysResidentWithoutOpeningSettings() {
        var session = RoutingSession()
        session.finishLaunching(atLogin: true)
        #expect(session.keepsRunning)
        #expect(!session.keepsEditorOpen)
        #expect(session.hidesEditor)
        let ticket = session.receiveURL()
        #expect(!session.isRoutingLaunch)
        #expect(!session.shouldTerminate(after: ticket))
        session.openEditor()
        #expect(!session.hidesEditor)
        #expect(session.keepsRunning)
        #expect(!session.shouldTerminate(after: ticket))
    }

    @Test func routingDoesNotCloseAnExistingEditor() {
        var session = RoutingSession()
        #expect(!session.isRoutingLaunch)
        session.openEditor()
        session.finishLaunching()
        let ticket = session.receiveURL()
        #expect(session.keepsEditorOpen)
        #expect(!session.shouldTerminate(after: ticket))
    }

    @Test func onlyTheLatestURLMayEndARoutingLaunch() {
        var session = RoutingSession()
        let first = session.receiveURL()
        #expect(session.isRoutingLaunch)
        session.finishLaunching()
        let second = session.receiveURL()
        #expect(!session.shouldTerminate(after: first))
        #expect(session.shouldTerminate(after: second))
    }

    @Test func openingSettingsCancelsPendingTermination() {
        var session = RoutingSession()
        let ticket = session.receiveURL()
        session.openEditor()
        #expect(!session.shouldTerminate(after: ticket))
    }
}
