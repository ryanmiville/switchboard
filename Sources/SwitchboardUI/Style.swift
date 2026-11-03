import AppKit
import SwiftUI
import SwitchboardCore

// The pieces that make the window read like System Settings on macOS 26: coloured pane icons,
// real browser icons, a header card at the top of each pane, and Liquid Glass where macOS has it
// (macOS 26), with the nearest material before that.

extension Pane {
    /// The pane icon's fill, as System Settings colours its sidebar icons.
    var tint: Color {
        switch self {
        case .general: Color(nsColor: .systemGray)
        case .routing: Color(nsColor: .systemBlue)
        case .quickSwitch: Color(nsColor: .systemOrange)
        }
    }

    /// The line under the pane's title in its header card.
    var summary: String {
        switch self {
        case .general: "Where unmatched links open, starting at login, link history, and the settings file."
        case .routing: "Rules that send links to a browser profile. The first rule that matches wins."
        case .quickSwitch: "A shortcut that opens the page in front in another profile, ignoring the rules."
        }
    }
}

/// A white symbol on a coloured rounded square, as System Settings draws pane icons.
struct PaneIcon: View {
    let pane: Pane
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [pane.tint.opacity(0.85), pane.tint], startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: size * 0.04, y: size * 0.03)
    }
}

/// A white symbol on a small coloured rounded square, for rows, as System Settings marks them.
struct SymbolTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(color.gradient)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}

/// A browser's own app icon, or the generic app icon when it isn't installed.
struct BrowserIcon: View {
    let locator: String
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: Self.icon(locator))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    static func icon(_ locator: String) -> NSImage {
        if !locator.isEmpty, FileManager.default.fileExists(atPath: locator) {
            return NSWorkspace.shared.icon(forFile: locator)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

/// The card at the top of a pane: its icon, title and what it is for, centred, as each System
/// Settings pane opens.
struct PaneHeader: View {
    let pane: Pane

    var body: some View {
        VStack(spacing: 8) {
            PaneIcon(pane: pane, size: 52)
            Text(pane.title).font(.title2.weight(.semibold))
            Text(pane.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 24)
    }
}

/// A row's leading icon and title with an optional caption, the shape of most rows in Settings.
struct RowLabel<Icon: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension RowLabel where Icon == EmptyView {
    init(title: String, caption: String? = nil) {
        self.init(title: title, caption: caption) { EmptyView() }
    }
}

extension View {
    /// Liquid Glass in `shape` on macOS 26; a regular material before it.
    @ViewBuilder
    func glass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// The prominent glass button style on macOS 26; the bordered prominent style before it.
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// The glass button style on macOS 26; the bordered style before it.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
