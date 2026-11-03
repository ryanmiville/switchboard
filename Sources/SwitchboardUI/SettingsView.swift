import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The settings window: a sidebar of panes, the notices that need the person, and the pane.
public struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    /// The window's size; it doesn't resize.
    public static let size = CGSize(width: 860, height: 620)

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Notices(model: model)
                Group {
                    switch model.pane {
                    case .general: GeneralPane(model: model)
                    case .routing: RoutingPane(model: model)
                    case .quickSwitch: QuickSwitchPane(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .sheet(item: draftBinding) { _ in RuleSheet(model: model) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.allCases) { pane in
                Button {
                    model.pane = pane
                } label: {
                    Label(pane.title, systemImage: pane.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.pane == pane ? Color.accentColor.opacity(0.18) : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pane-\(pane.rawValue)")
            }
            Spacer()
            SaveStatus(model: model)
                .padding(.horizontal, 10)
        }
        .padding(12)
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private var draftBinding: Binding<DraftID?> {
        Binding(
            get: { model.draft.map { DraftID(id: $0.id) } },
            set: { if $0 == nil { model.draft = nil } })
    }
}

struct DraftID: Identifiable, Hashable {
    let id: RuleID
}

/// "Saved", "Saving…", or why not.
struct SaveStatus: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let text =
            model.editor.loadError != nil
            ? "Not saving" : model.editor.hasUnsavedChanges ? "Unsaved changes" : "All changes saved"
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("save-status")
    }
}

/// Problems that need the person: a link that didn't open, a file that can't be read or saved.
struct Notices: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 8) {
            if let failure = model.failure {
                Banner(
                    title: "The link couldn’t be opened",
                    message: "\(failure.reason) Fix the issue here, or copy the link to open it yourself.",
                    detail: failure.url
                ) {
                    Button("Copy Link") { model.copyFailedLink() }
                    Button("Dismiss") { model.failure = nil }
                }
            }
            if let error = model.editor.loadError {
                Banner(title: "Settings couldn’t be read", message: error) {
                    Button("Reload") { model.edit { $0.reload() } }
                    Button("Reveal in Finder") { model.revealConfigFile() }
                }
            } else if model.editor.conflict {
                Banner(title: "Settings changed elsewhere", message: model.editor.saveError ?? "") {
                    Button("Keep My Changes") { model.edit { $0.keepMine() } }
                    Button("Use Saved Settings") { model.edit { $0.reload() } }
                }
            } else if let error = model.editor.saveError {
                Banner(title: "Changes couldn’t be saved", message: error) {
                    Button("Retry") { model.flush() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, model.failure != nil || model.editor.loadError != nil || model.editor.saveError != nil ? 16 : 0)
    }
}

struct Banner<Actions: View>: View {
    let title: String
    let message: String
    var detail: String?
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        .truncationMode(.middle).textSelection(.enabled)
                }
                HStack { actions }.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.35)))
    }
}

/// A pane's title and a line about it.
struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

/// A red line under a field.
struct ErrorText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }
}
