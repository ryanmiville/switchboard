import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// What the Quick Switch panel needs from the app.
public struct PickerServices {
    /// Saves pending Settings edits before a pick (a manual pick ignores the rules either way).
    public var flushSettings: @MainActor () -> Void
    /// Saves the picker settings through the settings window's editor, so the two never write over
    /// each other.
    public var savePicker: @MainActor (PickerSettings) -> Void
    /// Brings the browser forward after opening a link in it.
    public var activate: @MainActor (BrowserInfo) -> Void
    public var openAutomationSettings: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void
    public var close: @MainActor () -> Void
    /// The time history records.
    public var now: @MainActor () -> Timestamp

    public init(
        flushSettings: @escaping @MainActor () -> Void,
        savePicker: @escaping @MainActor (PickerSettings) -> Void,
        activate: @escaping @MainActor (BrowserInfo) -> Void,
        openAutomationSettings: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void, close: @escaping @MainActor () -> Void,
        now: @escaping @MainActor () -> Timestamp
    ) {
        self.flushSettings = flushSettings
        self.savePicker = savePicker
        self.activate = activate
        self.openAutomationSettings = openAutomationSettings
        self.openSettings = openSettings
        self.close = close
        self.now = now
    }

    /// No system calls, and a fixed time.
    public static var shown: PickerServices {
        PickerServices(
            flushSettings: {}, savePicker: { _ in }, activate: { _ in }, openAutomationSettings: {},
            openSettings: {}, close: {}, now: { Timestamp(1_761_757_451) })
    }
}

@MainActor
public final class PickerModel: ObservableObject {
    @Published public var state = PickerState()
    @Published public var reading = false
    public let store: ConfigStore
    public let history: HistoryStore
    public let browsers: Browsers
    public let services: PickerServices
    /// The last destination opened, for tests.
    public private(set) var opened: Destination?

    public init(store: ConfigStore, history: HistoryStore, browsers: Browsers, services: PickerServices) {
        self.store = store
        self.history = history
        self.browsers = browsers
        self.services = services
        state.refresh(store: store, browsers: browsers)
    }

    public func refresh() { state.refresh(store: store, browsers: browsers) }

    /// A new summon: lists the destinations again and clears the last link.
    public func reset() {
        state.reset()
        opened = nil
        refresh()
    }

    public func tabRead(_ result: Result<String, TabError>) {
        reading = false
        state.tabRead(result)
    }

    public func open(_ index: Int) {
        services.flushSettings()
        guard let destination = state.open(index, browsers: browsers, history: history, now: services.now())
        else {
            return
        }
        opened = destination
        if let browser = browsers.at(destination.browser) { services.activate(browser) }
        services.close()
    }

    public func toggleFavorite(_ index: Int) {
        if let settings = state.toggleFavorite(index, browsers: browsers) { services.savePicker(settings) }
    }

    /// The panel's height for what it shows now.
    public var height: CGFloat {
        let shown = state.shown
        let rows = CGFloat(min(max(shown.count, 2), 7))
        return 118 + rows * PickerView.rowHeight + (state.error == nil ? 0 : 86) + (reading ? 24 : 0)
    }

    public static let width: CGFloat = 560
}

/// The Quick Switch panel, drawn as a Spotlight-style floating glass panel: the link at the top,
/// then the destinations, favorites first, and the keys at the bottom.
public struct PickerView: View {
    @ObservedObject var model: PickerModel

    public init(model: PickerModel) {
        self.model = model
    }

    static let rowHeight: CGFloat = 50
    static let corner: CGFloat = 26

    public var body: some View {
        let shown = model.state.shown
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Paste an HTTP or HTTPS link", text: $model.state.link)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .onSubmit { model.open(model.state.selected) }
                    .accessibilityIdentifier("picker-link")
                Button {
                    model.services.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Quick Switch settings")
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
            Divider().opacity(0.5)
            if model.reading {
                Label("Reading the current tab…", systemImage: "hourglass")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.top, 8)
            }
            if let error = model.state.error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if model.state.needsPermission {
                            Button("Automation Settings…") { model.services.openAutomationSettings() }
                                .controlSize(.small)
                                .glassButton()
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(.horizontal, 12).padding(.top, 10)
            }
            if shown.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.badge.minus").font(.system(size: 24)).foregroundStyle(
                        .tertiary)
                    Text("No destinations are shown.").font(.headline)
                    Text("Choose some in Settings → Quick Switch.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(shown.enumerated()), id: \.element.destination) { index, choice in
                            ChoiceRow(
                                choice: choice, number: number(of: index),
                                selected: index == model.state.selected,
                                open: { model.open(index) }, star: { model.toggleFavorite(index) })
                        }
                    }
                    .padding(8)
                }
            }
            Divider().opacity(0.5)
            HStack(spacing: 14) {
                KeyHint(keys: "↑↓", label: "Choose")
                KeyHint(keys: "↩", label: "Open")
                KeyHint(keys: "⌘1–9", label: "Favorite")
                Spacer()
                KeyHint(keys: "esc", label: "Close")
            }
            .padding(.horizontal, 20)
            .frame(height: 36)
            // ⌘1–⌘9 open a favorite, arrows move the selection, Escape closes. Return opens through
            // the link field's submit.
            keyboardButtons
        }
        .frame(width: PickerModel.width)
        .glass(in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
    }

    private func number(of index: Int) -> Int? {
        let favorites = model.state.shown.indices.filter { model.state.shown[$0].favorite }
        return favorites.firstIndex(of: index).map { $0 + 1 }.flatMap { $0 <= 9 ? $0 : nil }
    }

    private var keyboardButtons: some View {
        ZStack {
            ForEach(1..<10) { n in
                Button("") { if let i = model.state.favorite(n) { model.open(i) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
            Button("") { model.state.moveSelection(by: 1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { model.state.moveSelection(by: -1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { model.services.close() }.keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// A key and what it does, in the panel's footer.
struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.caption.weight(.semibold).monospaced())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(label).font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

/// One destination: the browser's icon, the profile and browser, its favorite number, and a star.
struct ChoiceRow: View {
    let choice: Choice
    let number: Int?
    let selected: Bool
    let open: () -> Void
    let star: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BrowserIcon(locator: choice.destination.browser, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(choice.profileName).font(.body.weight(.medium))
                Text(choice.error ?? choice.browserName)
                    .font(.caption)
                    .foregroundStyle(choice.error == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
            }
            Spacer()
            if let number {
                Text("⌘\(number)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button(action: star) {
                Image(systemName: choice.favorite ? "star.fill" : "star")
                    .foregroundStyle(choice.favorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: PickerView.rowHeight - 2)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}
