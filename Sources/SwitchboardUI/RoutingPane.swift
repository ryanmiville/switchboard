import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The ordered rules, as a list inside a grouped section with its controls along the bottom edge
/// (as System Settings shows Login Items), and a link tester.
struct RoutingPane: View {
    @ObservedObject var model: SettingsModel

    static let rowHeight: CGFloat = 48

    var body: some View {
        let e = model.editor
        let rules = e.config.rules
        let hidden = Dictionary(
            Shadowing.unreachable(rules).map { ($0.rule, $0.by) }, uniquingKeysWith: { first, _ in first })
        Form {
            NoticesSection(model: model)

            Section {
                if rules.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No Rules").font(.headline)
                        Text(
                            "Every link opens in the default destination. Add a rule to send some elsewhere."
                        )
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .accessibilityIdentifier("routing-empty")
                } else {
                    List(selection: $model.selected) {
                        ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                            RuleRow(index: index, rule: rule, hiddenBy: hidden[index], editor: e)
                                .frame(height: Self.rowHeight - 8)
                                .tag(rule.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    model.selected = rule.id
                                    model.editSelected()
                                }
                                .contextMenu {
                                    Button("Edit Rule…") {
                                        model.selected = rule.id
                                        model.editSelected()
                                    }
                                    Button("Delete Rule", role: .destructive) {
                                        model.selected = rule.id
                                        model.deleteSelected()
                                    }
                                }
                        }
                        .onMove { from, to in
                            guard let first = from.first else { return }
                            let id = rules[first].id
                            model.edit { $0.moveRule(id, to: to > first ? to - 1 : to) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(rules.count) * Self.rowHeight)
                    .accessibilityIdentifier("rules")
                }
                controls
            } header: {
                Text("Rules")
            } footer: {
                Footer("The first rule that matches a link wins. Drag rules to change their order.")
            }

            Section {
                TextField("Link", text: $model.testURL, prompt: Text("https://example.com/page"))
                    .accessibilityIdentifier("test-url")
                let link = model.testURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !link.isEmpty {
                    let result = Routing.describe(link, editor: model.editor)
                    Label(
                        result.text, systemImage: result.ok ? "arrow.right.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(result.ok ? Color.primary : Color.red)
                    .symbolRenderingMode(.multicolor)
                    .accessibilityIdentifier("test-result")
                }
            } header: {
                Text("Test a link")
            } footer: {
                Footer("Shows the rule and destination a link would get, without opening it.")
            }
        }
        .formStyle(.grouped)
    }

    /// +, −, move up and down, and Edit, along the list's bottom edge.
    private var controls: some View {
        HStack(spacing: 8) {
            ControlGroup {
                Button {
                    model.draft = .newRule()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a rule")
                Button {
                    model.deleteSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .help("Delete the selected rule")
                .disabled(model.selectedIndex == nil)
            }
            .fixedSize()
            ControlGroup {
                Button {
                    if let id = model.selected { model.edit { $0.moveRule(id, by: -1) } }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .help("Move up")
                .disabled((model.selectedIndex ?? 0) == 0)
                Button {
                    if let id = model.selected { model.edit { $0.moveRule(id, by: 1) } }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .help("Move down")
                .disabled(model.selectedIndex.map { $0 >= model.editor.config.rules.count - 1 } ?? true)
            }
            .fixedSize()
            Spacer()
            Button("Edit…") { model.editSelected() }
                .disabled(model.selectedIndex == nil)
        }
        .controlSize(.small)
    }
}

/// One rule: its position, how it matches, the pattern, and where it sends links.
struct RuleRow: View {
    let index: Int
    let rule: Rule
    let hiddenBy: Int?
    let editor: Editor

    var body: some View {
        let browser = editor.config.browser(of: rule)
        let resolves = (try? Profiles.directory(rule.profile, in: editor.profiles(of: browser))) != nil
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.condition.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                    Text(rule.value).lineLimit(1).truncationMode(.middle)
                }
                if let by = hiddenBy {
                    Label(
                        "Never matches: rule \(by + 1) always matches first",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(editor.profileName(browser: browser, profile: rule.profile))
                        .foregroundStyle(resolves ? Color.primary : Color.red)
                        .lineLimit(1)
                    Text(
                        rule.browser == nil
                            ? "\(editor.browserName(browser)) (default)" : editor.browserName(browser)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                BrowserIcon(locator: browser, size: 26)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The add/edit sheet, as a grouped form. Only Done changes the config.
struct RuleSheet: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if let draft = model.draft {
            let e = model.editor
            let browser = draft.browser ?? e.config.browser
            VStack(spacing: 0) {
                Form {
                    Section {
                        Picker("Match", selection: binding(\.condition)) {
                            ForEach(Condition.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        TextField(
                            "Pattern", text: binding(\.value), prompt: Text(placeholder(draft.condition))
                        )
                        .accessibilityIdentifier("draft-value")
                    } header: {
                        Text(draft.isNew ? "New Rule" : "Edit Rule").font(.headline)
                    } footer: {
                        Footer(hint(draft.condition))
                    }
                    Section("Open in") {
                        BrowserPicker(
                            title: "Browser", selection: draft.browser, browsers: e.installed, editor: e,
                            allowsDefault: true
                        ) { chosen in
                            model.draft?.selectBrowser(chosen, defaultBrowser: e.config.browser)
                        }
                        ProfilePicker(title: "Profile", browser: browser, selection: draft.profile, editor: e)
                        {
                            model.draft?.profile = $0
                        }
                    }
                    if let error = draft.error {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("draft-error")
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                HStack {
                    Spacer()
                    Button("Cancel") { model.draft = nil }
                        .keyboardShortcut(.cancelAction)
                    Button(draft.isNew ? "Add Rule" : "Done") { model.commitDraft() }
                        .keyboardShortcut(.defaultAction)
                        .prominentButton()
                }
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .frame(width: 500)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Draft, T>) -> Binding<T> {
        Binding(
            get: { model.draft![keyPath: keyPath] },
            set: { model.draft?[keyPath: keyPath] = $0 })
    }

    private func placeholder(_ condition: Condition) -> String {
        switch condition {
        case .domain: "github.com"
        case .contains: "acme"
        case .exact: "https://example.com/login"
        }
    }

    private func hint(_ condition: Condition) -> String {
        switch condition {
        case .domain: "The host, which also matches its subdomains."
        case .contains: "Text anywhere in the link, ignoring case."
        case .exact: "The whole link, ignoring case."
        }
    }
}
