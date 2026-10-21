// Keeps the launch/lifetime decision testable without running NSApplication.
struct RoutingSession {
    private(set) var keepsEditorOpen = false
    private var receivedURL = false
    private var latestTicket = 0

    var isRoutingLaunch: Bool { receivedURL && !keepsEditorOpen }

    mutating func finishLaunching() {
        if !receivedURL { openEditor() }
    }

    mutating func receiveURL() -> Int {
        receivedURL = true
        latestTicket += 1
        return latestTicket
    }

    mutating func openEditor() {
        keepsEditorOpen = true
    }

    func shouldTerminate(after ticket: Int) -> Bool {
        isRoutingLaunch && ticket == latestTicket
    }
}
