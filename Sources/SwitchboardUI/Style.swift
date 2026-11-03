import AppKit
import SwiftUI
import SwitchboardCore

// The pieces that make the window read like System Settings on macOS 26: coloured pane icons,
// real browser icons, and Liquid Glass for the Quick Switch panel (macOS 26), with the nearest
// material before that.

extension Pane {
    /// The pane icon's fill, as System Settings colours its sidebar icons.
    var tint: Color {
        switch self {
        case .general: Color(nsColor: .systemGray)
        case .routing: Color(nsColor: .systemBlue)
        case .quickSwitch: Color(nsColor: .systemOrange)
        }
    }

    /// What the pane is for, which the sidebar search also matches.
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

/// A browser's own app icon. An app with no icon of its own (or none installed) gets a globe
/// tile rather than the generic app placeholder.
struct BrowserIcon: View {
    let locator: String
    var size: CGFloat = 20

    var body: some View {
        if let icon = Self.icon(locator) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            SymbolTile(symbol: "globe", color: .gray, size: size * 0.86)
                .frame(width: size, height: size)
        }
    }

    static func icon(_ locator: String) -> NSImage? {
        guard !locator.isEmpty, let bundle = Bundle(path: locator) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        guard info["CFBundleIconFile"] != nil || info["CFBundleIconName"] != nil else { return nil }
        return NSWorkspace.shared.icon(forFile: locator)
    }
}

/// A section footer, left-aligned as System Settings writes them (SwiftUI trails them on macOS).
struct Footer: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(Glass.regular.tint(tint), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}

extension View {
    /// Liquid Glass in `shape` on macOS 26, and a regular material before it.
    func glass(in shape: some Shape, tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint))
    }

    /// The prominent button style. On macOS 26 the system draws it as Liquid Glass itself.
    func prominentButton() -> some View {
        buttonStyle(.borderedProminent)
    }
}

extension Color {
    /// Secondary text and symbols in a fixed label colour.
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
}
