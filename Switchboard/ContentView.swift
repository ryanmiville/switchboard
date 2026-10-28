import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable {
    case general, routing, quickSwitch

    var title: String {
        switch self {
        case .general: "General"
        case .routing: "Routing"
        case .quickSwitch: "Quick Switch"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .routing: "arrow.triangle.branch"
        case .quickSwitch: "keyboard"
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: ConfigViewModel
    @ObservedObject var picker: TabPickerController
    @ObservedObject var loginItem: LoginItemController
    var onOpen: (@escaping () -> Void) -> Void
    @Environment(\.openWindow) private var openWindow
    @AppStorage("settingsPane") private var storedPane = SettingsPane.general.rawValue
    @State private var selectedRuleID: UUID?
    @State private var draft: RouteDraft?
    @State private var testURL = ""

    private var pane: SettingsPane { SettingsPane(rawValue: storedPane) ?? .general }
    private var paneBinding: Binding<SettingsPane> {
        Binding(get: { pane }, set: { storedPane = $0.rawValue })
    }
    private var selectedRule: Route? {
        viewModel.config.routes.first { $0.id == selectedRuleID }
    }

    var body: some View {
        VStack(spacing: 0) {
            errors
            Group {
                switch pane {
                case .general: generalPane
                case .routing:
                    if viewModel.loadError != nil || viewModel.saveError != nil
                        || viewModel.profileError != nil
                    {
                        // Recovery banners can consume substantial space in a small settings window.
                        ScrollView { routingPane }
                    } else {
                        routingPane
                    }
                case .quickSwitch:
                    QuickSwitchSettings(viewModel: viewModel, picker: picker, model: picker.model)
                }
            }
            .disabled(viewModel.loadError != nil)
            Divider()
            saveStatus
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 760, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsWindowToolbar(selection: paneBinding).frame(width: 0, height: 0))
        .sheet(item: $draft) { draft in
            RuleEditorSheet(draft: draft, viewModel: viewModel) { edited in
                guard viewModel.commitRoute(edited) else { return false }
                selectedRuleID = edited.id
                return true
            }
        }
        .onAppear {
            onOpen { openWindow(id: "settings") }
            loginItem.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
            _ in
            loginItem.refresh()
        }
        .onChange(of: viewModel.config.routes.map(\.id)) { ids in
            if let selectedRuleID, !ids.contains(selectedRuleID) { self.selectedRuleID = nil }
        }
    }

    private var generalPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection("Opening links") {
                    HStack(spacing: 12) {
                        BrowserIcon(path: viewModel.config.browser, size: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Default destination").fontWeight(.medium)
                            Text(
                                destinationLabel(
                                    browser: viewModel.config.browser,
                                    profile: viewModel.config.defaultProfile)
                            )
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        }
                        Spacer(minLength: 20)
                        Button("Routing Settings…") { storedPane = SettingsPane.routing.rawValue }
                    }
                    Divider().padding(.vertical, 9)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Routing rules").fontWeight(.medium)
                            Text(ruleCount).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 20)
                        Button("Manage Rules…") { storedPane = SettingsPane.routing.rawValue }
                    }
                }
                SettingsSection("Quick Switch") {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Open the current tab in another profile").fontWeight(.medium)
                            Text("Uses the destination’s login and leaves the original tab open.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 20)
                        Text((viewModel.config.picker?.shortcut ?? .default).label)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Divider().padding(.vertical, 9)
                    HStack {
                        Text(favoriteCount).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Quick Switch Settings…") { storedPane = SettingsPane.quickSwitch.rawValue }
                    }
                }
                SettingsSection("Startup") {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Launch Switchboard at login").fontWeight(.medium)
                            Text("Starts in the menu bar with Settings closed.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 20)
                        Toggle(
                            "Launch Switchboard at login",
                            isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .fixedSize()
                        .accessibilityHint("Starts in the menu bar with Settings closed.")
                    }
                    if loginItem.needsApproval {
                        Text("Allow Switchboard in System Settings → General → Login Items.")
                            .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    if let error = loginItem.error {
                        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(
                            .top, 8)
                    }
                    if loginItem.needsApproval || loginItem.error != nil {
                        Button("Open Login Items…", action: loginItem.openSettings).padding(.top, 6)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 840)
            .frame(maxWidth: .infinity)
        }
    }

    private var routingPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Default destination") {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Browser").font(.callout).foregroundStyle(.secondary)
                        BrowserPicker(
                            label: "Default browser",
                            selection: Binding(
                                get: { viewModel.config.browser }, set: { viewModel.selectDefaultBrowser($0) }
                            ),
                            browsers: viewModel.availableBrowsers
                        )
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profile").font(.callout).foregroundStyle(.secondary)
                        ProfilePicker(
                            label: "Default profile", selection: $viewModel.config.defaultProfile,
                            profiles: viewModel.availableProfiles
                        )
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("Used for links that don’t match a rule.").font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Routing rules").font(.headline)
                    Text("First match wins. Drag rules to change their priority.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ZStack {
                        RoutingRulesTable(
                            rows: tableRows, selection: $selectedRuleID,
                            onEdit: editSelectedRule,
                            onDelete: deleteSelectedRule,
                            onMove: { viewModel.moveRoute(id: $0, toInsertionIndex: $1) }
                        )
                        if viewModel.config.routes.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.branch").font(.title2).foregroundStyle(
                                    .secondary)
                                Text("No routing rules yet").font(.headline)
                                Text("All links use your default destination.").foregroundStyle(.secondary)
                                Button("Add Your First Rule") { draft = RouteDraft(config: viewModel.config) }
                                    .padding(.top, 5)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                    Divider()
                    HStack(spacing: 0) {
                        Button {
                            draft = RouteDraft(config: viewModel.config)
                        } label: {
                            Image(systemName: "plus").frame(width: 26, height: 22).contentShape(Rectangle())
                        }
                        .keyboardShortcut("n", modifiers: .command)
                        .help("Add a rule").accessibilityLabel("Add rule")
                        Divider().frame(height: 14)
                        Button {
                            deleteSelectedRule()
                        } label: {
                            Image(systemName: "minus").frame(width: 26, height: 22).contentShape(Rectangle())
                        }
                        .help("Delete selected rule").accessibilityLabel("Delete selected rule")
                        .disabled(selectedRule == nil)
                        Spacer()
                        Button("Edit Rule…", action: editSelectedRule)
                            .disabled(selectedRule == nil)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
                .frame(minHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.10)))
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Test a URL").font(.headline)
                TextField("https://example.com", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Test URL")
                Text(
                    testURL.isEmpty
                        ? "Preview the matching rule and destination without opening the link." : preview
                )
                .font(.callout).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
    }

    private var tableRows: [RuleTableRow] {
        viewModel.config.routes.enumerated().map { index, route in
            let browser = route.browser ?? viewModel.config.browser
            return RuleTableRow(
                id: route.id, priority: index + 1,
                pattern: route.value.isEmpty ? "Empty pattern (ignored)" : route.value,
                condition: route.condition.label, browser: browser,
                destination: destinationLabel(browser: browser, profile: route.profile))
        }
    }

    private func destinationLabel(browser: String, profile: String) -> String {
        let name = viewModel.profiles(for: browser).first { $0.directory == profile }?.name
        return
            "\(browserName(browser)) · \(name ?? (profile.isEmpty ? "Choose a profile…" : "Unavailable: \(profile)"))"
    }

    private var ruleCount: String {
        let count = viewModel.config.routes.count
        return count == 0
            ? "All links use the default destination."
            : "\(count) \(count == 1 ? "rule" : "rules"), checked in order."
    }

    private var favoriteCount: String {
        let settings = viewModel.config.picker ?? PickerSettings()
        let count = settings.favorites.filter { settings.includes($0.destination) }.count
        return count == 0
            ? "Choose destinations and favorites in Quick Switch settings."
            : "\(count) favorite \(count == 1 ? "destination" : "destinations") in the picker."
    }

    private var preview: String {
        guard let url = URL(string: testURL), Router.isWebURL(url) else {
            return "Enter a complete HTTP or HTTPS URL, such as https://example.com."
        }
        let decision = Router(config: viewModel.config).decision(url: url)
        let destination = decision.destination
        let target = destinationLabel(browser: destination.browser, profile: destination.profile)
        if let route = decision.route,
            let index = viewModel.config.routes.firstIndex(where: { $0.id == route.id })
        {
            return "Rule \(index + 1) → \(target)"
        }
        return "Default → \(target)"
    }

    private func editSelectedRule() {
        guard let selectedRule else { return }
        draft = RouteDraft(config: viewModel.config, route: selectedRule)
    }

    private func deleteSelectedRule() {
        guard let selectedRule else { return }
        viewModel.deleteRoute(selectedRule)
        selectedRuleID = nil
    }

    @ViewBuilder private var errors: some View {
        if let error = viewModel.loadError {
            errorMessage("Settings couldn’t be loaded", error) {
                Button("Open Configuration File") { NSWorkspace.shared.open(viewModel.configURL) }
                Button("Retry Loading") { viewModel.reload() }
            }
        }
        if let error = viewModel.saveError {
            errorMessage("Changes haven’t been saved", error) { Button("Retry Saving") { viewModel.flush() } }
        }
        if let error = viewModel.profileError {
            errorMessage("Check browser profiles", error) {
                Button("Refresh Profiles") { viewModel.refreshProfiles() }
                Button("Review Destinations") { storedPane = SettingsPane.routing.rawValue }
            }
        }
    }

    private func errorMessage<Actions: View>(
        _ title: String, _ message: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle").fontWeight(.medium)
            ScrollView {
                Text(message).font(.callout).textSelection(.enabled).frame(
                    maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 70)
            HStack { actions() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.yellow.opacity(0.12))
    }

    private var saveStatus: some View {
        HStack {
            if viewModel.loadError != nil || viewModel.saveError != nil || viewModel.profileError != nil {
                Label("Review the settings above", systemImage: "exclamationmark.circle").foregroundStyle(
                    .secondary)
            } else if viewModel.hasUnsavedChanges {
                Text("Saving changes…").foregroundStyle(.secondary)
            } else {
                Label("All changes saved", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

private struct QuickSwitchSettings: View {
    @ObservedObject var viewModel: ConfigViewModel
    @ObservedObject var picker: TabPickerController
    @ObservedObject var model: TabPickerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection("Keyboard shortcut") {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Open the current tab in another profile").fontWeight(.medium)
                            Text("Click the shortcut to record a new one. Escape cancels.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 20)
                        ShortcutRecorder(
                            shortcut: viewModel.config.picker?.shortcut ?? .default,
                            onRecord: viewModel.setPickerShortcut, onRecordingChanged: picker.setRecording
                        )
                        .frame(width: 180)
                        .accessibilityLabel("Quick Switch keyboard shortcut")
                        Button("Reset") { viewModel.setPickerShortcut(.default) }
                    }
                    if let error = picker.shortcutError {
                        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(
                            .top, 10)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Destinations").font(.headline)
                            Text(
                                "Checked profiles appear in Quick Switch. Star favorites to put them first, with ⌘1–⌘9 shortcuts."
                            )
                            .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Refresh") { model.refresh() }
                    }
                    HStack {
                        Button("Favorites Only", action: model.showOnlyFavorites)
                        Button("Show All", action: model.showAllDestinations)
                        Spacer()
                        Text("\(model.choices.count) shown").font(.callout).foregroundStyle(.secondary)
                    }
                    if model.allChoices.isEmpty {
                        SettingsSection("Browsers & profiles") {
                            Text("No supported browsers were found.").fontWeight(.medium)
                            Text("Install a supported Chromium browser, then refresh.")
                                .font(.callout).foregroundStyle(.secondary).padding(.top, 5)
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.allChoices.enumerated()), id: \.element.id) { index, choice in
                                if index > 0 { Divider().padding(.leading, 82) }
                                favoriteRow(choice)
                            }
                        }
                        .background(
                            Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08)))
                    }
                    Text(
                        "Switchboard must be running to use the shortcut. Opening a tab keeps its original browser window open."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .onAppear { model.refresh() }
    }

    private func favoriteRow(_ choice: PickerChoice) -> some View {
        let number = model.favoriteNumber(for: choice)
        return HStack(alignment: .top, spacing: 12) {
            Toggle(
                "Show \(choice.label) in Quick Switch",
                isOn: Binding(get: { model.includes(choice) }, set: { model.setIncluded($0, for: choice) })
            )
            .labelsHidden().toggleStyle(.checkbox)
            .disabled(choice.destination.profile.isEmpty)
            .padding(.top, 5)
            BrowserIcon(path: choice.destination.browser, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(choice.profileName).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                Text(choice.browserDisplayName).font(.callout).foregroundStyle(.secondary)
                if let error = choice.error {
                    Text(error).font(.callout).foregroundStyle(.red).fixedSize(
                        horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            if let number, number <= 9 {
                Text("⌘\(number)").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                    .padding(.top, 5)
            }
            Button {
                model.toggleFavorite(choice)
            } label: {
                Image(systemName: choice.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(choice.isFavorite ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(!choice.isFavorite && (choice.error != nil || !model.includes(choice)))
            .help(choice.isFavorite ? "Remove favorite" : "Add favorite")
            .accessibilityLabel("\(choice.isFavorite ? "Remove" : "Add") favorite: \(choice.label)")
        }
        .padding(14)
    }
}

private struct RuleEditorSheet: View {
    @State var draft: RouteDraft
    @ObservedObject var viewModel: ConfigViewModel
    let onCommit: (RouteDraft) -> Bool
    @Environment(\.dismiss) private var dismiss
    @FocusState private var patternFocused: Bool
    @State private var profiles: [Profile] = []
    @State private var profileError: String?
    @State private var commitError: String?

    private var browser: String { draft.route.browser ?? viewModel.config.browser }
    private var canSave: Bool {
        !draft.route.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && profiles.contains(where: { $0.directory == draft.route.profile })
            && profileError == nil && viewModel.loadError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(draft.isNew ? "Add Rule" : "Edit Rule").font(.title2.weight(.semibold))
                Text("Choose which links match and where they open.").foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                editorRow("Match") {
                    SettingsPopUp(
                        label: "Match type",
                        selection: Binding(
                            get: { draft.route.condition.rawValue },
                            set: {
                                if let condition = Condition(rawValue: $0) {
                                    draft.route.condition = condition
                                }
                            }),
                        options: Condition.allCases.map { PopUpOption(value: $0.rawValue, title: $0.label) }
                    )
                }
                editorRow(draft.route.condition == .domain ? "Domain" : "URL pattern") {
                    VStack(alignment: .leading, spacing: 7) {
                        TextField(
                            draft.route.condition == .domain ? "example.com" : "URL pattern",
                            text: $draft.route.value
                        )
                        .textFieldStyle(.roundedBorder).focused($patternFocused)
                        .accessibilityLabel(draft.route.condition == .domain ? "Domain" : "URL pattern")
                        Text(matchHelp).font(.caption).foregroundStyle(.secondary).fixedSize(
                            horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                editorRow("Browser") {
                    BrowserPicker(
                        label: "Rule browser",
                        selection: Binding(
                            get: { draft.route.browser ?? "" },
                            set: {
                                draft.selectBrowser(
                                    $0.isEmpty ? nil : $0, defaultBrowser: viewModel.config.browser)
                            }
                        ), browsers: viewModel.availableBrowsers, defaultBrowser: viewModel.config.browser
                    ).labelsHidden()
                }
                editorRow("Profile") {
                    VStack(alignment: .leading, spacing: 7) {
                        ProfilePicker(
                            label: "Rule profile", selection: $draft.route.profile, profiles: profiles
                        ).labelsHidden()
                        if !draft.route.profile.isEmpty {
                            Text("\(draft.route.profile) in \(browserName(browser))").font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Choose a profile for this browser.").font(.caption).foregroundStyle(
                                .secondary)
                        }
                    }
                }
            }
            if let profileError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(profileError).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    Button("Refresh Profiles", action: refreshProfiles)
                }
            }
            if let commitError { Text(commitError).font(.callout).foregroundStyle(.red) }
            Text(priorityHelp).font(.callout).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Refresh Profiles", action: refreshProfiles)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(draft.isNew ? "Add Rule" : "Done", action: save)
                    .keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            refreshProfiles()
            patternFocused = true
        }
        .onChange(of: browser) { _ in refreshProfiles() }
    }

    private func editorRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label).frame(width: 80, alignment: .trailing)
            control().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var matchHelp: String {
        switch draft.route.condition {
        case .domain: "Matches this domain and its subdomains. Enter a host without https:// or a path."
        case .contains: "Matches text anywhere in the complete URL, ignoring case."
        case .exact: "Matches the complete URL, ignoring case."
        }
    }

    private var priorityHelp: String {
        if !draft.isNew, let index = viewModel.config.routes.firstIndex(where: { $0.id == draft.id }) {
            return "Rule \(index + 1) is checked in order. The first matching rule wins."
        }
        return "New rules are added at the bottom. Drag them in the list to change priority."
    }

    private func refreshProfiles() {
        do {
            profiles = try viewModel.discoverProfiles(for: browser)
            draft.selectOnlyProfile(in: profiles)
            profileError =
                profiles.isEmpty
                ? "No profiles were found in this browser. Create a browser profile, then refresh." : nil
        } catch {
            profiles = []
            profileError =
                "Profiles couldn’t be read. \(error.localizedDescription) Choose another browser or refresh to retry."
        }
    }

    private func save() {
        // Refresh before committing in case the browser removed or renamed a profile while editing.
        refreshProfiles()
        guard canSave else { return }
        guard onCommit(draft) else {
            commitError = "This rule couldn’t be updated. Cancel and reopen the rule from the current list."
            return
        }
        dismiss()
    }
}

private func browserName(_ path: String) -> String {
    ((path as NSString).lastPathComponent as NSString).deletingPathExtension
}

private struct BrowserIcon: View {
    let path: String
    let size: CGFloat
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct BrowserPicker: View {
    let label: String
    @Binding var selection: String
    let browsers: [InstalledBrowser]
    var defaultBrowser: String?

    private var options: [PopUpOption] {
        var options: [PopUpOption] = []
        if let defaultBrowser {
            options.append(PopUpOption(value: "", title: "Use default (\(browserName(defaultBrowser)))"))
        }
        if !browsers.contains(where: { $0.path == selection }), defaultBrowser == nil || !selection.isEmpty {
            options.append(
                PopUpOption(
                    value: selection,
                    title: selection.isEmpty ? "Choose a browser…" : "Unavailable: \(browserName(selection))")
            )
        }
        return options + browsers.map { PopUpOption(value: $0.path, title: browserName($0.path)) }
    }

    var body: some View { SettingsPopUp(label: label, selection: $selection, options: options) }
}

private struct ProfilePicker: View {
    let label: String
    @Binding var selection: String
    let profiles: [Profile]

    private var options: [PopUpOption] {
        var options = [PopUpOption(value: "", title: "Choose a profile…")]
        if !selection.isEmpty && !profiles.contains(where: { $0.directory == selection }) {
            options.append(PopUpOption(value: selection, title: "Unavailable: \(selection)"))
        }
        return options + profiles.map { PopUpOption(value: $0.directory, title: $0.name) }
    }

    var body: some View { SettingsPopUp(label: label, selection: $selection, options: options) }
}

private struct PopUpOption: Equatable {
    let value: String
    let title: String
}

// Native controls fill their proposed width, including long browser/profile display names.
private struct SettingsPopUp: NSViewRepresentable {
    let label: String
    @Binding var selection: String
    let options: [PopUpOption]
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton()
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let previous = context.coordinator.parent.options
        context.coordinator.parent = self
        if button.numberOfItems == 0 || previous != options {
            let menu = NSMenu()
            for option in options {
                let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
                item.representedObject = option.value
                menu.addItem(item)
            }
            button.menu = menu
        }
        if let index = options.firstIndex(where: { $0.value == selection }) { button.selectItem(at: index) }
        button.isEnabled = isEnabled
        button.toolTip = button.title
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(button.title)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: 24)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SettingsPopUp
        init(_ parent: SettingsPopUp) { self.parent = parent }
        @objc func select(_ sender: NSPopUpButton) {
            guard let value = sender.selectedItem?.representedObject as? String else { return }
            parent.selection = value
        }
    }
}

// A native preferences toolbar keeps navigation separate from each pane's controls on macOS 13+.
private struct SettingsWindowToolbar: NSViewRepresentable {
    @Binding var selection: SettingsPane

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindow = { [weak coordinator = context.coordinator] in coordinator?.install(on: $0) }
        return view
    }
    func updateNSView(_ view: WindowObserverView, context: Context) {
        context.coordinator.parent = self
        if let window = view.window { context.coordinator.install(on: window) }
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate {
        var parent: SettingsWindowToolbar
        private weak var installedWindow: NSWindow?
        init(_ parent: SettingsWindowToolbar) { self.parent = parent }

        func install(on window: NSWindow) {
            if installedWindow !== window {
                installedWindow = window
                let toolbar = NSToolbar(identifier: "SwitchboardSettings")
                toolbar.delegate = self
                toolbar.allowsUserCustomization = false
                toolbar.autosavesConfiguration = false
                toolbar.displayMode = .iconAndLabel
                window.toolbar = toolbar
                window.toolbarStyle = .preference
                window.tabbingMode = .disallowed
                window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
            window.title = parent.selection.title
            window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(parent.selection.rawValue)
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            SettingsPane.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
        }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }
        func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }
        func toolbar(
            _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            guard let pane = SettingsPane(rawValue: identifier.rawValue) else { return nil }
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = pane.title
            item.paletteLabel = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            item.target = self
            item.action = #selector(selectPane)
            return item
        }
        @objc private func selectPane(_ sender: NSToolbarItem) {
            guard let pane = SettingsPane(rawValue: sender.itemIdentifier.rawValue) else { return }
            parent.selection = pane
        }
    }
}

private final class WindowObserverView: NSView {
    var onWindow: (NSWindow) -> Void = { _ in }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow(window) }
    }
}

private struct RuleTableRow: Equatable {
    let id: UUID
    let priority: Int
    let pattern: String
    let condition: String
    let browser: String
    let destination: String
}

private struct RoutingRulesTable: NSViewRepresentable {
    let rows: [RuleTableRow]
    @Binding var selection: UUID?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMove: (UUID, Int) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = RulesTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.edit)
        table.onEdit = onEdit
        table.onDelete = onDelete
        table.isEnabled = isEnabled
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.rowHeight = 38
        table.intercellSpacing = NSSize(width: 10, height: 0)
        table.style = .inset
        table.setAccessibilityLabel("Routing rules. First matching rule wins.")
        for (id, title, width, minWidth) in [
            ("priority", "#", 34.0, 30.0), ("pattern", "URL pattern", 270.0, 180.0),
            ("condition", "Match", 90.0, 76.0), ("destination", "Destination", 310.0, 190.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = minWidth
            table.addTableColumn(column)
        }
        table.registerForDraggedTypes([Coordinator.pasteboardType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let previousRows = coordinator.parent.rows
        coordinator.parent = self
        guard let table = coordinator.table else { return }
        table.onEdit = onEdit
        table.onDelete = onDelete
        table.isEnabled = isEnabled
        coordinator.updating = true
        if previousRows != rows { table.reloadData() }
        let selectedIndex = rows.firstIndex { $0.id == selection }
        if table.selectedRow != (selectedIndex ?? -1) {
            table.selectRowIndexes(
                selectedIndex.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
        }
        coordinator.updating = false
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let pasteboardType = NSPasteboard.PasteboardType("dev.rymi.switchboard.routing-rule")
        var parent: RoutingRulesTable
        weak var table: RulesTableView?
        var updating = false
        init(_ parent: RoutingRulesTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            parent.selection =
                parent.rows.indices.contains(table.selectedRow) ? parent.rows[table.selectedRow].id : nil
        }
        @objc func edit() { parent.onEdit() }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.rows.indices.contains(row), let column = tableColumn?.identifier.rawValue else {
                return nil
            }
            let rule = parent.rows[row]
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = column == "pattern" ? .byTruncatingMiddle : .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            var inset: CGFloat = 0
            switch column {
            case "priority":
                label.stringValue = String(rule.priority)
                label.textColor = .secondaryLabelColor
            case "pattern": label.stringValue = rule.pattern
            case "condition":
                label.stringValue = rule.condition
                label.textColor = .secondaryLabelColor
            default:
                label.stringValue = rule.destination
                let image = NSImageView(image: NSWorkspace.shared.icon(forFile: rule.browser))
                image.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(image)
                cell.imageView = image
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 22),
                    image.heightAnchor.constraint(equalToConstant: 22),
                ])
                inset = 30
            }
            label.toolTip = label.stringValue
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: inset),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard parent.rows.indices.contains(row) else { return nil }
            let item = NSPasteboardItem()
            item.setString(parent.rows[row].id.uuidString, forType: Self.pasteboardType)
            return item
        }
        func tableView(
            _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
            proposedDropOperation operation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard parent.isEnabled, info.draggingSource as? NSTableView === tableView else { return [] }
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }
        func tableView(
            _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard info.draggingSource as? NSTableView === tableView,
                let value = info.draggingPasteboard.string(forType: Self.pasteboardType),
                let id = UUID(uuidString: value), parent.rows.contains(where: { $0.id == id })
            else { return false }
            parent.onMove(id, row)
            return true
        }
    }
}

private final class RulesTableView: NSTableView {
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    override func keyDown(with event: NSEvent) {
        guard selectedRow >= 0 else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 36: onEdit()
        case 51, 117: onDelete()
        default: super.keyDown(with: event)
        }
    }
}
