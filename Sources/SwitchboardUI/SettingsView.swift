import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The settings window, laid out as System Settings on macOS 26: a floating glass sidebar of panes
/// with coloured icons (the traffic lights sit in its top corner), and the selected pane as grouped
/// sections under its header card. Notices that need the person sit above the pane.
///
/// The sidebar is drawn here rather than by NavigationSplitView: the system's glass sidebar is
/// composited by the window server, so offscreen renders came out blank.
public struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    /// The window's size; it doesn't resize.
    public static let size = CGSize(width: 860, height: 640)

    public var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
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
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .sheet(item: draftBinding) { _ in RuleSheet(model: model) }
    }

    private var draftBinding: Binding<DraftID?> {
        Binding(
            get: { model.draft.map { DraftID(id: $0.id) } },
            set: { if $0 == nil { model.draft = nil } })
    }
}

/// The panes, as a floating glass panel inset from the window's edges.
struct Sidebar: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Room for the traffic lights, which sit inside the sidebar's top corner.
            Spacer().frame(height: 40)
            ForEach(Pane.allCases) { pane in
                let selected = model.pane == pane
                Button {
                    model.pane = pane
                } label: {
                    HStack(spacing: 9) {
                        PaneIcon(pane: pane, size: 22)
                        Text(pane.title)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.2) : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pane-\(pane.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            SaveStatus(model: model).padding(.horizontal, 8)
        }
        .padding(10)
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(8)
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
        .foregroundStyle(Color.secondaryLabel)
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
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(
                Color.orange.opacity(0.3), lineWidth: 0.5))
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
