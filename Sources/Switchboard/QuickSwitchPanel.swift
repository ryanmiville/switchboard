import AppKit
import Combine
import SwiftUI
import SwitchboardCore
import SwitchboardEditor
import SwitchboardMac
import SwitchboardUI

/// The Quick Switch panel: summoned by the shortcut over a browser, it reads that browser's current
/// tab and opens it in a destination chosen by hand.
@MainActor
final class QuickSwitchPanel {
    private let model: PickerModel
    private let holder: PanelHolder
    private var panel: Panel? { holder.panel }
    private var resize: AnyCancellable?

    init(
        store: ConfigStore, history: HistoryStore, browsers: Browsers, settings: SettingsModel,
        openSettings: @escaping @MainActor () -> Void
    ) {
        let holder = PanelHolder()
        self.holder = holder
        model = PickerModel(
            store: store, history: history, browsers: browsers,
            services: PickerServices(
                flushSettings: { settings.flush() },
                savePicker: { picker in
                    settings.edit { $0.setPicker(picker) }
                    settings.flush()
                },
                activate: { CurrentTab.activate($0) },
                openAutomationSettings: { CurrentTab.openAutomationSettings() },
                openSettings: {
                    holder.panel?.orderOut(nil)
                    settings.pane = .quickSwitch
                    openSettings()
                },
                close: { holder.panel?.orderOut(nil) }, now: { AppDelegate.now() }))
    }

    func refresh() { model.refresh() }

    /// The shortcut: remember the app in front, read its tab, and show the panel.
    func summon() {
        // Capture the app in front before this app activates or shows anything.
        let front = CurrentTab.frontmost()
        model.reset()
        if let front {
            model.reading = true
            let model = self.model
            DispatchQueue.global(qos: .userInitiated).async {
                let result = CurrentTab.read(front)
                Task { @MainActor in model.tabRead(result) }
            }
        } else {
            model.tabRead(.failure(.unsupportedBrowser))
        }
        let panel = self.panel ?? makePanel()
        panel.setContentSize(NSSize(width: PickerModel.width, height: model.height))
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        })
            ?? NSScreen.main
        {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(
                NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - 140))
        }
        bringToFront()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> Panel {
        let panel = Panel(
            contentRect: NSRect(x: 0, y: 0, width: PickerModel.width, height: model.height),
            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Quick Switch"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: PickerView(model: model))
        panel.onResignKey = { [weak panel] in panel?.orderOut(nil) }
        resize = model.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                panel.setContentSize(NSSize(width: PickerModel.width, height: self.model.height))
            }
        }
        holder.panel = panel
        return panel
    }
}

/// The panel, reachable from the model's services before the panel exists.
@MainActor
final class PanelHolder {
    var panel: Panel?
}

/// A panel that takes keys, closes with Escape, and goes away when the person goes elsewhere.
final class Panel: NSPanel {
    var onResignKey: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey()
    }
}
