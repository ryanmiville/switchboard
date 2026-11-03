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
        flushSettings: @escaping @MainActor () -> Void, savePicker: @escaping @MainActor (PickerSettings) -> Void,
        activate: @escaping @MainActor (BrowserInfo) -> Void, openAutomationSettings: @escaping @MainActor () -> Void,
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
        guard let destination = state.open(index, browsers: browsers, history: history, now: services.now()) else {
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
        return 150 + rows * 44 + (state.error == nil ? 0 : 70)
    }

    public static let width: CGFloat = 460
}

/// The Quick Switch panel: the link, then the destinations, favorites first.
public struct PickerView: View {
    @ObservedObject var model: PickerModel

    public init(model: PickerModel) {
        self.model = model
    }

    public var body: some View {
        let shown = model.state.shown
        VStack(alignment: .leading, spacing: 10) {
            Text("Open in…").font(.headline)
            TextField("Paste an HTTP or HTTPS link", text: $model.state.link)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.open(model.state.selected) }
                .accessibilityIdentifier("picker-link")
            if model.reading {
                Text("Reading the current tab…").font(.callout).foregroundStyle(.secondary)
            }
            if let error = model.state.error {
                VStack(alignment: .leading, spacing: 6) {
                    ErrorText(error)
                    if model.state.needsPermission {
                        Button("Automation Settings…") { model.services.openAutomationSettings() }
                    }
                }
            }
            if shown.isEmpty {
                Text("No destinations are shown. Choose some in Settings → Quick Switch.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(shown.enumerated()), id: \.element.destination) { index, choice in
                            ChoiceRow(
                                choice: choice, number: number(of: index), selected: index == model.state.selected,
                                open: { model.open(index) }, star: { model.toggleFavorite(index) })
                        }
                    }
                }
            }
            HStack {
                Button("Settings…") { model.services.openSettings() }
                Spacer()
                Button("Cancel") { model.services.close() }.keyboardShortcut(.cancelAction)
                Button("Open") { model.open(model.state.selected) }.keyboardShortcut(.defaultAction)
                    .disabled(shown.isEmpty)
            }
            // ⌘1–⌘9 open a favorite; arrows move the selection.
            keyboardButtons
        }
        .padding(16)
        .frame(width: PickerModel.width)
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
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

struct ChoiceRow: View {
    let choice: Choice
    let number: Int?
    let selected: Bool
    let open: () -> Void
    let star: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: star) {
                Image(systemName: choice.favorite ? "star.fill" : "star")
                    .foregroundStyle(choice.favorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.profileName).font(.body.weight(.medium))
                Text(choice.browserName).font(.caption).foregroundStyle(.secondary)
                if let error = choice.error {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if let number {
                Text("⌘\(number)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.2) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}
