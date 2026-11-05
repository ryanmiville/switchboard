import AppKit

/// What macOS made of the settings window: its toolbar, title bar and view classes, in words, to go
/// with the window shots (`WindowShot`). `Switchboard --describe-window` opens Settings, prints this
/// and quits; scripts/launch-check runs it.
@MainActor
enum WindowReport {
    static func describe() -> String {
        var lines = ["macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for window in NSApp.windows where window.isVisible {
            lines.append(
                "window \(type(of: window)) “\(window.title)” \(Int(window.frame.width))×\(Int(window.frame.height))"
            )
            if let toolbar = window.toolbar {
                lines.append(
                    "  toolbar: style \(name(window.toolbarStyle)), \(toolbar.items.count) items: "
                        + toolbar.items.map { $0.itemIdentifier.rawValue }.joined(separator: ", "))
            } else {
                lines.append("  toolbar: none")
            }
            lines.append(
                "  title \(window.titleVisibility == .visible ? "visible" : "hidden"), separator "
                    + "\(name(window.titlebarSeparatorStyle)), full-size content "
                    + "\(window.styleMask.contains(.fullSizeContentView)), resizable "
                    + "\(window.styleMask.contains(.resizable))")
            lines.append("  views:")
            var budget = 400
            tree(window.contentView?.superview ?? window.contentView, depth: 2, budget: &budget, into: &lines)
        }
        return lines.joined(separator: "\n")
    }

    /// The view tree as class names and frames, depth first, cut off after `budget` lines.
    private static func tree(_ view: NSView?, depth: Int, budget: inout Int, into lines: inout [String]) {
        guard let view, budget > 0 else { return }
        budget -= 1
        let f = view.frame
        lines.append(
            String(repeating: "  ", count: depth)
                + "\(type(of: view)) \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height))"
                + (view.isHidden ? " hidden" : ""))
        for subview in view.subviews { tree(subview, depth: depth + 1, budget: &budget, into: &lines) }
    }

    private static func name(_ style: NSWindow.ToolbarStyle) -> String {
        switch style {
        case .automatic: "automatic"
        case .expanded: "expanded"
        case .preference: "preference"
        case .unified: "unified"
        case .unifiedCompact: "unifiedCompact"
        @unknown default: "\(style.rawValue)"
        }
    }

    private static func name(_ style: NSTitlebarSeparatorStyle) -> String {
        switch style {
        case .automatic: "automatic"
        case .none: "none"
        case .line: "line"
        case .shadow: "shadow"
        @unknown default: "\(style.rawValue)"
        }
    }
}
