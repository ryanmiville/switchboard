import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The ordered rules, their controls, and a URL tester.
struct RoutingPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let e = model.editor
        let rules = e.config.rules
        let hidden = Dictionary(
            Shadowing.unreachable(rules).map { ($0.rule, $0.by) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Routing rules", subtitle: "First match wins. Drag rules to change their priority.")
            if rules.isEmpty {
                Text("No rules yet. Every link opens in the default destination.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("routing-empty")
            } else {
                List(selection: $model.selected) {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        RuleRow(index: index, rule: rule, hiddenBy: hidden[index], editor: e)
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
                                Button("Delete Rule") {
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
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .accessibilityIdentifier("rules")
            }
            controls
            Divider()
            tester
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
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
            Button {
                if let id = model.selected { model.edit { $0.moveRule(id, by: -1) } }
            } label: {
                Image(systemName: "arrow.up")
            }
            .help("Move up")
            .disabled((model.selectedIndex ?? 0) == 0)
            Button {
                if let id = model.selected { model.edit { $0.moveRule(id, by: 1) } }
            } label: {
                Image(systemName: "arrow.down")
            }
            .help("Move down")
            .disabled(model.selectedIndex.map { $0 >= model.editor.config.rules.count - 1 } ?? true)
            Spacer()
            Button("Edit Rule…") { model.editSelected() }
                .disabled(model.selectedIndex == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var tester: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Test a URL").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            TextField("https://example.com", text: $model.testURL)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("test-url")
            let link = model.testURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if link.isEmpty {
                Text("Preview the matching rule and destination without opening the link.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let result = Routing.describe(link, editor: model.editor)
                Text(result.text).font(.callout).foregroundStyle(result.ok ? Color.primary : Color.red)
                    .accessibilityIdentifier("test-result")
            }
        }
        .padding(20)
    }
}

struct RuleRow: View {
    let index: Int
    let rule: Rule
    let hiddenBy: Int?
    let editor: Editor

    var body: some View {
        let browser = editor.config.browser(of: rule)
        HStack(spacing: 12) {
            Text("\(index + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
            Text(rule.condition.label).font(.callout).foregroundStyle(.secondary).frame(
                width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.value).lineLimit(1).truncationMode(.middle)
                if let by = hiddenBy {
                    Text("never matches: rule \(by + 1) always matches first").font(.caption).foregroundStyle(
                        .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    "\(editor.browserName(browser)) · \(editor.profileName(browser: browser, profile: rule.profile))"
                )
                .lineLimit(1)
                .foregroundStyle(profileResolves(browser) ? Color.primary : Color.red)
                if rule.browser == nil {
                    Text("default browser").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func profileResolves(_ browser: String) -> Bool {
        (try? Profiles.directory(rule.profile, in: editor.profiles(of: browser))) != nil
    }
}

/// The add/edit sheet. Only Done changes the config.
struct RuleSheet: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if let draft = model.draft {
            let e = model.editor
            let browser = draft.browser ?? e.config.browser
            VStack(alignment: .leading, spacing: 14) {
                Text(draft.isNew ? "Add Rule" : "Edit Rule").font(.title3.weight(.semibold))
                Form {
                    Picker("Match", selection: binding(\.condition)) {
                        ForEach(Condition.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            "Pattern", text: binding(\.value), prompt: Text(placeholder(draft.condition))
                        )
                        .accessibilityIdentifier("draft-value")
                        Text(hint(draft.condition)).font(.caption).foregroundStyle(.secondary)
                    }
                    BrowserPicker(
                        title: "Browser", selection: draft.browser, browsers: e.installed, editor: e,
                        allowsDefault: true
                    ) { chosen in
                        model.draft?.selectBrowser(chosen, defaultBrowser: e.config.browser)
                    }
                    ProfilePicker(title: "Profile", browser: browser, selection: draft.profile, editor: e) {
                        model.draft?.profile = $0
                    }
                }
                .formStyle(.columns)
                if let error = draft.error {
                    ErrorText(error).accessibilityIdentifier("draft-error")
                }
                HStack {
                    Spacer()
                    Button("Cancel") { model.draft = nil }
                        .keyboardShortcut(.cancelAction)
                    Button(draft.isNew ? "Add Rule" : "Done") { model.commitDraft() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 480)
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
