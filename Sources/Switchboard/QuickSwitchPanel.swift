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
    private var commandMonitor: Any?
    private var keyMonitor: Any?
    private var numbersSoon: Task<Void, Never>?

    /// How long ⌘ is held before the destinations show their numbers, so a quick ⌘1 doesn't flash them.
    static let numbersDelay = Duration.milliseconds(700)

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
                Task { @MainActor in model.tabRead(result, browserID: front.id) }
            }
        } else {
            model.tabRead(.failure(.unsupportedBrowser), browserID: nil)
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
        // The shadow is taken from what the window has drawn, so take it again once it has.
        panel.invalidateShadow()
        Task { @MainActor in panel.invalidateShadow() }
    }

    /// Shows the destinations' numbers once ⌘ alone has been held a moment, and hides them as soon
    /// as it's let go.
    private func commandChanged(held: Bool) {
        numbersSoon?.cancel()
        guard held else {
            model.showsNumbers = false
            return
        }
        numbersSoon = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.numbersDelay)
            guard !Task.isCancelled else { return }
            self?.model.showsNumbers = true
        }
    }

    /// Clips the panel's content to its rounded corners. A borderless window's shadow and edge
    /// follow what it draws, and the glass draws its whole rectangle faintly, which gave the panel
    /// square corners behind the rounded glass.
    private static func rounded(_ content: NSView) -> NSView {
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.cornerRadius = PickerView.corner
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        content.frame = clip.bounds
        content.autoresizingMask = [.width, .height]
        clip.addSubview(content)
        return clip
    }

    /// AppKit's glass with the panel's corner radius, holding the SwiftUI content. The glass gives
    /// the borderless window its rounded shape, so its shadow and edge follow the corners. Before
    /// macOS 26, a rounded material does the same.
    private static func glass(around content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = PickerView.corner
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        let r = PickerView.corner
        let mask = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        mask.resizingMode = .stretch
        effect.maskImage = mask
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }

    private func makePanel() -> Panel {
        // Borderless and clear, so the glass's rounded shape is the panel's shape, as Spotlight's.
        let panel = Panel(
            contentRect: NSRect(x: 0, y: 0, width: PickerModel.width, height: model.height),
            styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Quick Switch"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Summoned from the keyboard many times a day, so it appears and goes at once.
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: PickerView(model: model))
        panel.contentView = Self.rounded(Self.glass(around: host))
        panel.onResignKey = { [weak self, weak panel] in
            self?.commandChanged(held: false)
            panel?.orderOut(nil)
        }
        // ↑ and ↓ (or ⌃N and ⌃P) and Esc act on the list even while the search field has the
        // cursor, which would otherwise take them for itself and leave the first row chosen.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let key = PanelKey(event)
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let key, let self, self.panel?.isKeyWindow == true else { return false }
                switch key {
                case .down: self.model.state.moveSelection(by: 1)
                case .up: self.model.state.moveSelection(by: -1)
                case .escape: self.model.escape()
                }
                return true
            }
            return handled ? nil : event
        }
        commandMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            // Local monitors run on the main thread.
            MainActor.assumeIsolated {
                if let self, self.panel?.isKeyWindow == true { self.commandChanged(held: held) }
            }
            return event
        }
        resize = model.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                panel.setContentSize(NSSize(width: PickerModel.width, height: self.model.height))
                panel.invalidateShadow()
            }
        }
        holder.panel = panel
        return panel
    }
}

/// The keys the panel handles itself, whatever has the cursor.
enum PanelKey: Sendable {
    case down, up, escape

    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty {
            switch event.keyCode {
            case 125: self = .down  // ↓
            case 126: self = .up  // ↑
            case 53: self = .escape  // Esc
            default: return nil
            }
        } else if modifiers == .control {
            // By letter, not key position, so it follows the keyboard layout.
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "n": self = .down
            case "p": self = .up
            default: return nil
            }
        } else {
            return nil
        }
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
