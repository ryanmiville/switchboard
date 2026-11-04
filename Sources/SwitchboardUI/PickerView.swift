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
    /// ⌘ has been held for a moment, so each destination shows the number that opens it.
    @Published public var showsNumbers = false
    /// Counts summons, so the panel puts the cursor back in its search field each time.
    @Published public private(set) var summons = 0
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

    /// A new summon: lists the destinations again and clears the last link and search.
    public func reset() {
        state.reset()
        opened = nil
        showsNumbers = false
        summons += 1
        refresh()
    }

    /// What was read from the browser with bundle identifier `browserID`.
    public func tabRead(_ result: Result<BrowserTab, TabError>, browserID: String?) {
        reading = false
        state.tabRead(result, browserID: browserID, installed: browsers.installed())
    }

    public var query: String {
        get { state.query }
        set { state.setQuery(newValue) }
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

    /// Escape clears the search first, as Spotlight does, then closes.
    public func escape() {
        if state.query.isEmpty { services.close() } else { query = "" }
    }

    /// Whether the line under the search field shows: the link, or that it's being read.
    var showsLink: Bool { reading || !state.link.isEmpty }

    /// The panel's height for what it shows now.
    public var height: CGFloat {
        let rows = CGFloat(min(max(state.shown.count, 2), 7))
        return 74 + (showsLink ? 24 : 0) + rows * PickerView.rowHeight + (state.error == nil ? 0 : 86)
    }

    public static let width: CGFloat = 560
}

/// The Quick Switch panel's content, Spotlight-style: a search field that narrows the
/// destinations, the link being switched under it, then the destinations, favorites first. Hold ⌘
/// to see the number that opens each. The panel puts it in AppKit's glass, with the corner below,
/// so the window's shape and shadow are the glass's.
public struct PickerView: View {
    @ObservedObject var model: PickerModel
    @FocusState private var searching: Bool

    public init(model: PickerModel) {
        self.model = model
    }

    static let rowHeight: CGFloat = 50
    public static let corner: CGFloat = 26

    public var body: some View {
        let shown = model.state.shown
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Switch to…", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        .focused($searching)
                        .onSubmit { model.open(model.state.selected) }
                        .accessibilityIdentifier("picker-search")
                    Button {
                        model.services.openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Quick Switch settings")
                }
                .frame(height: 34)
                if model.showsLink {
                    Label {
                        Text(model.reading ? "Reading the current tab…" : Self.display(model.state.link))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: model.reading ? "hourglass" : "link")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
                    .frame(height: 22)
                    .accessibilityIdentifier("picker-link")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider().opacity(0.5)
            if let error = model.state.error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if model.state.needsPermission {
                            Button("Automation Settings…") { model.services.openAutomationSettings() }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
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
                    Image(
                        systemName: model.state.query.isEmpty
                            ? "rectangle.stack.badge.minus" : "magnifyingglass"
                    )
                    .font(.system(size: 24)).foregroundStyle(.tertiary)
                    if model.state.query.isEmpty {
                        Text("No destinations are shown.").font(.headline)
                        Text("Choose some in Settings → Quick Switch.").font(.callout).foregroundStyle(
                            .secondary)
                    } else {
                        Text("No profile matches “\(model.state.query)”.").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(shown.enumerated()), id: \.element.destination) { index, choice in
                            ChoiceRow(
                                choice: choice,
                                number: model.showsNumbers && index < 9 ? index + 1 : nil,
                                selected: index == model.state.selected,
                                open: { model.open(index) })
                        }
                    }
                    .padding(8)
                }
            }
            // ⌘1–⌘9 open a destination, arrows move the selection, Escape clears the search and
            // then closes. Return opens through the search field's submit.
            keyboardButtons
        }
        .frame(width: PickerModel.width)
        .onAppear { searching = true }
        .onReceive(model.$summons) { _ in searching = true }
    }

    /// The link without its scheme, which says nothing here. It's only shown, never opened from.
    static func display(_ link: String) -> String {
        for scheme in ["https://", "http://"] where link.hasPrefix(scheme) {
            return String(link.dropFirst(scheme.count))
        }
        return link
    }

    private var keyboardButtons: some View {
        ZStack {
            ForEach(1..<10) { n in
                Button("") { if let i = model.state.number(n) { model.open(i) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
            Button("") { model.state.moveSelection(by: 1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { model.state.moveSelection(by: -1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { model.escape() }.keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// One destination: the browser's icon, the profile and browser, and, while ⌘ is held, the number
/// that opens it.
struct ChoiceRow: View {
    let choice: Choice
    let number: Int?
    let selected: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BrowserIcon(locator: choice.destination.browser, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(choice.profileName).font(.body.weight(.medium))
                Text(choice.error ?? choice.browserName)
                    .font(.caption)
                    .foregroundStyle(choice.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(2)
            }
            Spacer()
            if let number {
                Text("⌘\(number)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
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
