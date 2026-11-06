import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The ordered rules, as a table inside a grouped section with its controls along the bottom edge
/// (as System Settings shows Login Items), and a link tester.
struct RoutingPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let e = model.editor
        let rules = e.config.rules
        let unreachable = Shadowing.unreachable(rules)
        let hidden = Dictionary(unreachable.map { ($0.rule, $0.by) }, uniquingKeysWith: { first, _ in first })
        let fixes = Dictionary(
            unreachable.compactMap { u in Shadowing.fix(rules, u).map { (u.rule, $0) } },
            uniquingKeysWith: { first, _ in first })
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
                    RulesTable(
                        rules: rules, hiddenBy: hidden, fixes: fixes, editor: e, selection: $model.selected,
                        onEdit: { model.editSelected() }, onDelete: { model.deleteSelected() },
                        onMove: { id, to in model.edit { $0.moveRule(id, to: to) } },
                        onMoveAbove: { id, to in model.moveAbove(id, to: to) }
                    )
                    // Up to eight rows show at once; the table scrolls the rest.
                    .frame(height: CGFloat(min(max(rules.count, 3), 8)) * RulesTable.rowHeight + 10)
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
                    model.draft = .newRule(
                        profile: model.editor.firstProfile(of: model.editor.config.browser))
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
    /// Where moving this rule makes it match again, when it never matches.
    let fix: Int?
    let editor: Editor
    var onMoveAbove: (Int) -> Void = { _ in }

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
                    HStack(spacing: 8) {
                        Label(
                            "Never matches: rule \(by + 1) always matches first",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        if let fix {
                            Button("Move Above Rule \(fix + 1)") { onMoveAbove(fix) }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .help("Move this rule above rule \(fix + 1), so it matches first")
                                .accessibilityIdentifier("move-above-\(index + 1)")
                        }
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(editor.profileName(browser: browser, profile: rule.profile))
                        .foregroundStyle(resolves ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
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

/// The add/edit sheet, as a grouped form with the sheet's own Cancel and Done. Only Done changes the
/// config. Scene renders draw the form alone: the buttons belong to the sheet, which they can't show.
struct RuleSheet: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if let draft = model.draft {
            let e = model.editor
            let browser = draft.browser ?? e.config.browser
            let preview = draft.preview(rules: e.config.rules, recent: model.recentLinks)
            Form {
                Section {
                    Picker(
                        "Match",
                        selection: Binding(
                            get: { model.draft?.condition ?? .domain },
                            set: { model.draft?.selectCondition($0) })
                    ) {
                        ForEach(Condition.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    // A bordered field filling the row after its label, so a long link reads from
                    // its start.
                    HStack(spacing: 12) {
                        Text("Pattern")
                        TextField(
                            "Pattern",
                            text: Binding(
                                get: { model.draft?.value ?? "" }, set: { model.draft?.enterPattern($0) }),
                            prompt: Text(placeholder(draft.condition))
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("draft-value")
                    }
                } header: {
                    Text(draft.isNew ? "New Rule" : "Edit Rule").font(.headline)
                } footer: {
                    if let preview {
                        PatternPreview(preview: preview)
                    } else {
                        Footer(hint(draft.condition))
                    }
                }
                Section("Open in") {
                    BrowserPicker(
                        title: "Browser", selection: draft.browser, browsers: e.installed, editor: e,
                        allowsDefault: true
                    ) { chosen in
                        model.draft?.selectBrowser(
                            chosen, defaultBrowser: e.config.browser,
                            firstProfile: e.firstProfile(of: chosen ?? e.config.browser))
                    }
                    ProfilePicker(title: "Profile", browser: browser, selection: draft.profile, editor: e) {
                        model.draft?.profile = $0
                    }
                }
                // A problem the preview already shows isn't repeated.
                if let error = draft.error, error != preview?.problem {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("draft-error")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            // SwiftUI puts these along the bottom of a sheet on macOS, with Return and Escape.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.draft = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.isNew ? "Add Rule" : "Done") { model.commitDraft() }
                }
            }
            .frame(width: 500)
            .fixedSize(horizontal: false, vertical: true)
        }
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

/// Under the pattern, as it is typed: what it matches, why it can't match, and which recent links
/// it would have matched.
struct PatternPreview: View {
    let preview: RulePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let summary = preview.summary { Text(summary) }
            if let problem = preview.problem { warning(problem) }
            if let hidden = preview.hiddenBy { warning(hidden) }
            if let recent = preview.recent {
                Text(recent.text).padding(.top, 2)
                ForEach(recent.examples, id: \.self) { link in
                    Text(link)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 10)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pattern-preview")
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
