import Testing

@testable import SwitchboardUI

// The settings window's back and forward buttons walk the panes shown, like System Settings.
@MainActor
struct PaneHistoryTests {
    @Test func backAndForwardRetraceThePanesShown() throws {
        let scene = try Scenes.make("general")
        defer { scene.remove() }
        let model = scene.settings
        #expect(model.backPanes.isEmpty && model.forwardPanes.isEmpty)

        model.pane = .routing
        model.pane = .quickSwitch
        model.goBack()
        #expect(model.pane == .routing)
        model.goBack()
        #expect(model.pane == .general)
        #expect(model.backPanes.isEmpty)
        model.goForward()
        #expect(model.pane == .routing)
        #expect(model.forwardPanes == [.quickSwitch])
    }

    @Test func showingAPaneAfterGoingBackForgetsTheWayForward() throws {
        let scene = try Scenes.make("general")
        defer { scene.remove() }
        let model = scene.settings
        model.pane = .routing
        model.goBack()
        model.pane = .quickSwitch
        #expect(model.forwardPanes.isEmpty)
        #expect(model.backPanes == [.general])
    }

    @Test func choosingThePaneOnShowAddsNothing() throws {
        let scene = try Scenes.make("general")
        defer { scene.remove() }
        scene.settings.pane = .general
        #expect(scene.settings.backPanes.isEmpty)
    }
}
