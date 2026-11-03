import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The settings window, laid out as System Settings on macOS 26: a sidebar of panes with coloured
/// icons (Liquid Glass on macOS 26, from the split view itself), and the selected pane as grouped
/// sections under its header card. Notices that need the person sit above the pane.
public struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    /// The window's size; it doesn't resize.
    public static let size = CGSize(width: 860, height: 640)

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                Notices(model: model)
                Group {
                    switch model.pane {
                    case .general: GeneralPane(model: model)
                    case .routing: RoutingPane(model: model)
                    case .quickSwitch: QuickSwitchPane(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle(model.pane.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: draftBinding) { _ in RuleSheet(model: model) }
    }

    private var sidebar: some View {
        List(selection: paneBinding) {
            ForEach(Pane.allCases) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneIcon(pane: pane, size: 22)
                }
                .padding(.vertical, 2)
                .tag(pane)
                .accessibilityIdentifier("pane-\(pane.rawValue)")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SaveStatus(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
    }

    private var paneBinding: Binding<Pane?> {
        Binding(get: { model.pane }, set: { if let pane = $0 { model.pane = pane } })
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

/// "All changes saved", or why not.
struct SaveStatus: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let saving = model.editor.loadError == nil && !model.editor.hasUnsavedChanges
        Label(
            model.editor.loadError != nil
                ? "Not saving" : model.editor.hasUnsavedChanges ? "Unsaved changes" : "All changes saved",
            systemImage: saving ? "checkmark.circle" : "exclamationmark.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("save-status")
    }
}

/// Problems that need the person: a link that didn't open, a file that can't be read or saved.
struct Notices: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let shown = model.failure != nil || model.editor.loadError != nil || model.editor.saveError != nil
        VStack(spacing: 10) {
            if let failure = model.failure {
                Banner(
                    symbol: "link.badge.plus", title: "The link couldn’t be opened",
                    message: "\(failure.reason) Fix the issue here, or copy the link to open it yourself.",
                    detail: failure.url
                ) {
                    Button("Copy Link") { model.copyFailedLink() }
                    Button("Dismiss") { model.failure = nil }
                }
            }
            if let error = model.editor.loadError {
                Banner(symbol: "doc.badge.ellipsis", title: "Settings couldn’t be read", message: error) {
                    Button("Reload") { model.edit { $0.reload() } }
                    Button("Reveal in Finder") { model.revealConfigFile() }
                }
            } else if model.editor.conflict {
                Banner(
                    symbol: "arrow.triangle.2.circlepath", title: "Settings changed elsewhere",
                    message: model.editor.saveError ?? ""
                ) {
                    Button("Keep My Changes") { model.edit { $0.keepMine() } }
                    Button("Use Saved Settings") { model.edit { $0.reload() } }
                }
            } else if let error = model.editor.saveError {
                Banner(symbol: "exclamationmark.icloud", title: "Changes couldn’t be saved", message: error) {
                    Button("Retry") { model.flush() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, shown ? 14 : 0)
    }
}

/// A notice as a tinted glass card, with its recovery actions.
struct Banner<Actions: View>: View {
    var symbol = "exclamationmark.triangle.fill"
    let title: String
    let message: String
    var detail: String?
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        .truncationMode(.middle).textSelection(.enabled)
                }
                HStack { actions }.padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), tint: .orange.opacity(0.15))
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
