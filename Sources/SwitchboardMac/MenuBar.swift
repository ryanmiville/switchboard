import AppKit
import SwitchboardCore

/// What the menu-bar menu asks the app to do.
public enum MenuAction: Sendable {
    /// Open the current page in another profile (the Quick Switch panel).
    case quickSwitch
    case openSettings
    case quit
}

/// The menu-bar item and its menu. Releasing it removes the item.
@MainActor
public final class MenuBar: NSObject {
    private let item: NSStatusItem
    private let onAction: (MenuAction) -> Void
    private let quickSwitch: NSMenuItem

    public init(onAction: @escaping (MenuAction) -> Void) {
        self.onAction = onAction
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        quickSwitch = NSMenuItem(title: "Quick Switch…", action: nil, keyEquivalent: "")
        super.init()
        if let button = item.button {
            button.image = Self.icon()
            button.toolTip = Identity.appName
            button.setAccessibilityLabel(Identity.appName)
        }
        let menu = NSMenu()
        quickSwitch.action = #selector(chooseQuickSwitch)
        quickSwitch.target = self
        menu.addItem(quickSwitch)
        let settings = NSMenuItem(title: "Settings…", action: #selector(chooseSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit \(Identity.appName)", action: #selector(chooseQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    /// Shows the registered shortcut next to Quick Switch, as text (the item can't take a global one).
    public func setShortcutHint(_ hint: String?) {
        quickSwitch.title = hint.map { "Quick Switch…   \($0)" } ?? "Quick Switch…"
    }

    public func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func chooseQuickSwitch() { onAction(.quickSwitch) }
    @objc private func chooseSettings() { onAction(.openSettings) }
    @objc private func chooseQuit() { onAction(.quit) }

    /// The template icon the bundle script copies into Contents/Resources, or a symbol when it
    /// isn't there (a `swift run` outside the bundle).
    private static func icon() -> NSImage? {
        let image =
            Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf").flatMap {
                NSImage(contentsOf: $0)
            }
            ?? NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: Identity.appName)
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        return image
    }
}

/// Brings this app forward, as opening Settings from the menu-bar item does.
@MainActor
public func bringToFront() {
    NSApplication.shared.activate(ignoringOtherApps: true)
}
