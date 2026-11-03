import AppKit
import ServiceManagement
import SwitchboardEditor

/// Launch at login for the app bundle this process runs from, through ServiceManagement. Calls can
/// block while macOS asks a system service, so the app makes them off the main thread.
public struct LoginItem: Sendable {
    public init() {}

    public func status() -> LoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    /// Turns it on or off and returns the status afterwards. Respects a change made in System
    /// Settings instead of re-registering an item the person turned off there.
    public func setEnabled(_ enabled: Bool) throws -> LoginStatus {
        let before = status()
        if enabled && before == .disabled {
            try SMAppService.mainApp.register()
        } else if !enabled && before != .disabled {
            try SMAppService.mainApp.unregister()
        }
        return status()
    }

    /// Opens System Settings → General → Login Items.
    public func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
