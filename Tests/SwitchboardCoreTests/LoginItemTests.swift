import Foundation
import ServiceManagement
import Testing

@testable import SwitchboardCore

@MainActor
struct LoginItemTests {
    private final class FakeService {
        var status = SMAppService.Status.notRegistered
        var failure: Error?
        var registrations = 0
        var unregistrations = 0
        var settingsOpened = 0

        var service: LoginItemService {
            LoginItemService(
                status: { self.status },
                register: {
                    self.registrations += 1
                    if let failure = self.failure { throw failure }
                    self.status = .enabled
                },
                unregister: {
                    self.unregistrations += 1
                    if let failure = self.failure { throw failure }
                    self.status = .notRegistered
                },
                openSettings: { self.settingsOpened += 1 })
        }
    }

    @Test func enablingAndDisablingUsesSystemState() {
        let fake = FakeService()
        let controller = LoginItemController(service: fake.service)
        #expect(fake.registrations == 0)
        #expect(!controller.isEnabled)
        controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(controller.error == nil)
        controller.setEnabled(true)
        #expect(fake.registrations == 1)
        controller.setEnabled(false)
        #expect(!controller.isEnabled)
        #expect(fake.unregistrations == 1)
        controller.setEnabled(false)
        #expect(fake.unregistrations == 1)
    }

    @Test func failuresRetainActualStateAndAllowRetry() {
        let fake = FakeService()
        fake.failure = NSError(domain: "TestLoginItem", code: 1)
        let controller = LoginItemController(service: fake.service)
        controller.setEnabled(true)
        #expect(!controller.isEnabled)
        #expect(controller.error?.contains("couldn’t be enabled") == true)
        fake.failure = nil
        controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(controller.error == nil)
        fake.failure = NSError(domain: "TestLoginItem", code: 2)
        controller.setEnabled(false)
        #expect(controller.isEnabled)
        #expect(controller.error?.contains("couldn’t be disabled") == true)
    }

    @Test func externalChangesAndApprovalAreRespected() {
        let fake = FakeService()
        fake.status = .enabled
        let controller = LoginItemController(service: fake.service)
        fake.status = .requiresApproval
        controller.refresh()
        #expect(!controller.isEnabled)
        #expect(controller.needsApproval)
        controller.setEnabled(true)
        #expect(fake.registrations == 0)
        #expect(controller.needsApproval)
        controller.openSettings()
        #expect(fake.settingsOpened == 1)
        fake.status = .enabled
        controller.refresh()
        #expect(controller.isEnabled)
        #expect(!controller.needsApproval)
    }

    @Test func registrationWithoutEnablementDoesNotReportSuccess() {
        let controller = LoginItemController(
            service: LoginItemService(status: { .notFound }, register: {}, unregister: {}, openSettings: {}))
        controller.setEnabled(true)
        #expect(!controller.isEnabled)
        #expect(controller.error?.contains("hasn’t applied") == true)
    }
}
