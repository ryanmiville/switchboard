import AppKit
import SwiftUI
import SwitchboardCore
import SwitchboardUI

/// The app's scenes. SwiftUI owns the settings window, so macOS gives it the System Settings
/// treatment (the glass sidebar under the traffic lights, the unified toolbar with the pane's
/// title), and the menu-bar item. The AppKit side (links, the shortcut, the app's lifetime, the
/// Quick Switch panel) lives in `AppDelegate`.
struct SwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var menuBar = MenuBarState.shared

    var body: some Scene {
        Window(Identity.appName, id: SettingsWindow.id) {
            SettingsWindow(delegate: delegate)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.showSettings() }
                    .keyboardShortcut(",")
            }
        }

        MenuBarExtra(isInserted: $menuBar.shown) {
            Button("Quick Switch\(menuBar.shortcutHint.map { "   \($0)" } ?? "")…") {
                delegate.summonPicker()
            }
            Button("Settings…") { delegate.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit \(Identity.appName)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            MenuBarLabel(opener: delegate.opener)
        }
    }
}

/// The settings window's content. It reports when it appears, so a window SwiftUI opens at launch
/// can be closed again when the launch only delivers links.
struct SettingsWindow: View {
    static let id = "settings"

    @ObservedObject var delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView(model: delegate.settings)
            .onAppear {
                delegate.opener.capture(openWindow)
                delegate.settingsWindowAppeared()
            }
            .onDisappear { delegate.settingsWindowClosed() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
                _ in
                delegate.settings.refresh()
            }
    }
}

/// The menu-bar icon. It also hands the app SwiftUI's `openWindow`, which only views can read.
struct MenuBarLabel: View {
    let opener: WindowOpener
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.icon)
            .onAppear { opener.capture(openWindow) }
            .accessibilityLabel(Identity.appName)
    }

    /// The template icon the bundle script copies into Contents/Resources, or a symbol outside
    /// the bundle (`swift run`).
    @MainActor static let icon: NSImage = {
        let image =
            Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf").flatMap {
                NSImage(contentsOf: $0)
            }
            ?? NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: Identity.appName)
            ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

/// Opens the settings window from AppKit code. SwiftUI's `openWindow` comes from a view's
/// environment, so the first view to appear hands it over; a request made before that waits.
@MainActor
final class WindowOpener {
    private var open: OpenWindowAction?
    private var pending = false

    func capture(_ action: OpenWindowAction) {
        open = action
        if pending {
            pending = false
            action(id: SettingsWindow.id)
        }
    }

    func openSettings() {
        if let open {
            open(id: SettingsWindow.id)
        } else {
            pending = true
        }
    }
}
