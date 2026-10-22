import Combine
import ServiceManagement

struct LoginItemService {
    var status: () -> SMAppService.Status = { SMAppService.mainApp.status }
    var register: () throws -> Void = { try SMAppService.mainApp.register() }
    var unregister: () throws -> Void = { try SMAppService.mainApp.unregister() }
    var openSettings: () -> Void = { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var error: String?
    private let service: LoginItemService

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    init(service: LoginItemService = LoginItemService()) {
        self.service = service
        status = service.status()
    }

    func refresh() {
        status = service.status()
    }

    func setEnabled(_ enabled: Bool) {
        refresh()
        error = nil
        // Respect a change made in System Settings instead of re-registering a denied item.
        guard enabled ? (status != .enabled && status != .requiresApproval) : status != .notRegistered
        else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            self.error =
                "Launch at login couldn’t be \(enabled ? "enabled" : "disabled"). \(error.localizedDescription) Try again or check Login Items in System Settings."
        }
        refresh()
        if error == nil && !needsApproval && isEnabled != enabled {
            error = "macOS hasn’t applied this change. Try again or check Login Items in System Settings."
        }
    }

    func openSettings() {
        service.openSettings()
    }
}
