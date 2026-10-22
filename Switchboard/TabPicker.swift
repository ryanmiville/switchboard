import AppKit
import Combine
import SwiftUI

@MainActor
final class TabPickerModel: ObservableObject {
    @Published var urlString = ""
    @Published private(set) var error: String?
    @Published private(set) var needsAutomationPermission = false
    @Published private(set) var allChoices: [PickerChoice] = []

    var choices: [PickerChoice] {
        guard let settings = viewModel.config.picker else { return allChoices }
        return allChoices.filter { settings.includes($0.destination) }
    }

    var panelHeight: CGFloat {
        176 + CGFloat(min(5, max(2, choices.count))) * 72 + (error == nil ? 0 : 120)
    }

    let viewModel: ConfigViewModel
    var reader = CurrentTabReader()
    var catalog = PickerCatalog()
    var browsers: () -> [InstalledBrowser] = { BrowserDiscovery.chromiumBrowsers() }
    var launch: (URL, Destination) throws -> Void = { try BrowserLauncher().launch(url: $0, destination: $1) }

    init(viewModel: ConfigViewModel) {
        self.viewModel = viewModel
    }

    func prepare(source: CurrentTabSource?) {
        error = nil
        needsAutomationPermission = false
        urlString = ""
        refresh()
        do {
            urlString = try reader.read(source: source).absoluteString
        } catch {
            self.error = error.localizedDescription
            needsAutomationPermission = (error as? CurrentTabError) == .automationDenied
        }
    }

    func refresh() {
        allChoices = catalog.choices(
            browsers: browsers(), favorites: viewModel.config.picker?.favorites ?? [],
            destinations: viewModel.config.picker?.destinations ?? [])
    }

    func toggleFavorite(_ choice: PickerChoice) {
        viewModel.toggleFavorite(choice)
        refresh()
    }

    func includes(_ choice: PickerChoice) -> Bool {
        viewModel.config.picker?.includes(choice.destination) ?? true
    }

    func setIncluded(_ included: Bool, for choice: PickerChoice) {
        viewModel.setPickerDestination(choice.destination, included: included, choices: allChoices)
        refresh()
    }

    func showOnlyFavorites() {
        viewModel.showOnlyPickerFavorites()
        refresh()
    }

    func showAllDestinations() {
        viewModel.showAllPickerDestinations()
        refresh()
    }

    func favoriteNumber(for choice: PickerChoice) -> Int? {
        choices.filter(\.isFavorite).firstIndex { $0.id == choice.id }.map { $0 + 1 }
    }

    func open(_ choice: PickerChoice) -> Bool {
        // A favorite cannot recover a URL that permission failure prevented us from reading.
        if urlString.isEmpty && needsAutomationPermission { return false }
        error = nil
        needsAutomationPermission = false
        guard includes(choice) else {
            error =
                "This destination is hidden from Quick Switch. Choose another destination or enable it in Settings."
            return false
        }
        guard choice.error == nil else {
            error = choice.error
            return false
        }
        guard let url = URL(string: urlString), Router.isWebURL(url) else {
            error = "Enter a complete HTTP or HTTPS link, such as https://example.com."
            return false
        }
        guard viewModel.flush() else {
            error =
                viewModel.loadError ?? viewModel.saveError ?? viewModel.profileError
                ?? "Your settings couldn’t be saved. Open Settings to retry."
            return false
        }
        do {
            // A manual selection intentionally bypasses automatic routing rules.
            try launch(url, choice.destination)
            return true
        } catch {
            self.error =
                "\(error.localizedDescription) Refresh the destinations or open Settings to fix the issue, then retry."
            return false
        }
    }
}

@MainActor
final class TabPickerController: ObservableObject {
    @Published private(set) var shortcutError: String?
    @Published private(set) var registeredShortcut: KeyboardShortcut?
    let model: TabPickerModel
    var sourceBrowser: () -> CurrentTabSource? = {
        guard let application = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = application.bundleIdentifier
        else { return nil }
        return CurrentTabSource(
            bundleIdentifier: bundleIdentifier, processIdentifier: application.processIdentifier)
    }
    var activateBrowser: (String) -> Void = { path in
        if let bundleID = Bundle(path: path)?.bundleIdentifier {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?
                .activate(options: [.activateIgnoringOtherApps])
        }
    }
    private let shortcut = GlobalShortcut()
    private var subscription: AnyCancellable?
    private var panelSubscription: AnyCancellable?
    private var panel: TabPickerPanel?
    private var isRecording = false

    init(viewModel: ConfigViewModel) {
        model = TabPickerModel(viewModel: viewModel)
    }

    func start() {
        guard subscription == nil else { return }
        model.viewModel.initializePicker()
        shortcut.onPress = { [weak self] in self?.show() }
        subscription = model.viewModel.$config.sink { [weak self] config in
            self?.register(config.picker?.shortcut ?? .default)
        }
    }

    private func register(_ value: KeyboardShortcut) {
        guard !isRecording else { return }
        do {
            try shortcut.register(value)
            registeredShortcut = value
            shortcutError = nil
        } catch {
            shortcutError = error.localizedDescription
            if let previous = registeredShortcut {
                do {
                    try shortcut.register(previous)
                    shortcutError = "\(error.localizedDescription) \(previous.label) is still active."
                } catch {
                    registeredShortcut = nil
                    shortcutError =
                        "The shortcut couldn’t be registered or restored. Record another shortcut or use the menu-bar button."
                }
            }
        }
    }

    func setRecording(_ recording: Bool) {
        isRecording = recording
        if recording {
            shortcut.stop()
        } else {
            register(model.viewModel.config.picker?.shortcut ?? .default)
        }
    }

    func show() {
        // Capture the source before activating Switchboard or showing any windows.
        let source = sourceBrowser()
        if let panel, panel.isVisible,
            source?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        model.prepare(source: source)
        if panel == nil {
            let panel = TabPickerPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: model.panelHeight),
                styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Quick Switch"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.contentView = NSHostingView(
                rootView: TabPickerView(
                    model: model, onOpen: { [weak self] choice in self?.open(choice) },
                    onCancel: { [weak panel] in panel?.orderOut(nil) },
                    onSettings: { [weak self] in
                        self?.panel?.orderOut(nil)
                        self?.onSettings()
                    }))
            self.panel = panel
            panelSubscription = model.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.panel?.isVisible == true else { return }
                    self.panel?.setContentSize(NSSize(width: 460, height: self.model.panelHeight))
                }
            }
        }
        panel?.setContentSize(NSSize(width: 460, height: model.panelHeight))
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    var onSettings: () -> Void = {}

    private func open(_ choice: PickerChoice) {
        guard model.open(choice) else { return }
        panel?.orderOut(nil)
        activateBrowser(choice.destination.browser)
    }
}

final class TabPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

private struct TabPickerView: View {
    @ObservedObject var model: TabPickerModel
    let onOpen: (PickerChoice) -> Void
    let onCancel: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Link to open").font(.callout).foregroundStyle(.secondary)
                TextField("Paste an HTTP or HTTPS link", text: $model.urlString)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Link to open")
                    .help(model.urlString)
            }
            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                if model.needsAutomationPermission {
                    Button("Automation Settings…") {
                        if let url = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                        {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            Text("Open in").font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if model.choices.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No destinations to show").fontWeight(.medium)
                            Text(
                                "Choose the browser profiles you want in Quick Switch settings, or refresh to check for installed browsers."
                            )
                            .font(.callout).foregroundStyle(.secondary)
                            Button("Choose Destinations…", action: onSettings).padding(.top, 4)
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(model.choices) { choice in
                            choiceRow(choice)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Opens a new tab. The original tab stays open.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Settings…", action: onSettings)
                Button("Refresh") { model.refresh() }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 460, height: model.panelHeight)
    }

    private func choiceRow(_ choice: PickerChoice) -> some View {
        let number = model.favoriteNumber(for: choice)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    onOpen(choice)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: choice.destination.browser))
                            .resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.profileName).fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(choice.browserDisplayName).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let number, number <= 9 {
                            Text("⌘\(number)").font(.caption.monospaced()).foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(choice.error != nil)
                .modifier(FavoriteKey(number: number))
                .help("\(choice.label) · \(choice.destination.profile)")
                .accessibilityLabel(choice.label)
                Button {
                    model.toggleFavorite(choice)
                } label: {
                    Image(systemName: choice.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .disabled(!choice.isFavorite && choice.error != nil)
                .help(choice.isFavorite ? "Remove favorite" : "Add favorite")
                .accessibilityLabel("\(choice.isFavorite ? "Remove" : "Add") favorite: \(choice.label)")
            }
            if let error = choice.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(choice.isFavorite ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct FavoriteKey: ViewModifier {
    let number: Int?

    @ViewBuilder func body(content: Content) -> some View {
        if let number, number <= 9 {
            content.keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
        } else {
            content
        }
    }
}
