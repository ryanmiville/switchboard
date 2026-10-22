// Keeps the launch/lifetime decision testable without running NSApplication.
struct RoutingSession {
    private(set) var keepsEditorOpen = false
    private(set) var keepsRunning = false
    private var receivedURL = false
    private var latestTicket = 0

    var isRoutingLaunch: Bool { receivedURL && !keepsRunning }
    var hidesEditor: Bool { !keepsEditorOpen }

    mutating func finishLaunching(atLogin: Bool = false) {
        if atLogin || !receivedURL { startResident() }
    }

    mutating func startResident() {
        keepsRunning = true
    }

    mutating func receiveURL() -> Int {
        receivedURL = true
        latestTicket += 1
        return latestTicket
    }

    mutating func openEditor() {
        keepsEditorOpen = true
        startResident()
    }

    func shouldTerminate(after ticket: Int) -> Bool {
        isRoutingLaunch && ticket == latestTicket
    }
}
