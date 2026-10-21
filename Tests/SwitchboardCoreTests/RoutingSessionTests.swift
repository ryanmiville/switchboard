import Testing

@testable import SwitchboardCore

struct RoutingSessionTests {
    @Test func routingDoesNotCloseAnExistingEditor() {
        var session = RoutingSession()
        #expect(!session.isRoutingLaunch)
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
