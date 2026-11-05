import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The settings window, built from SwiftUI's own components so it matches System Settings: a
/// NavigationSplitView (the system's glass sidebar, with the traffic lights inside it and a search
/// field), the pane's title in the toolbar, and the pane as a grouped Form.
///
/// Offscreen renders can't capture the system sidebar or Liquid Glass, which the window server
/// composites, so scene renders show those areas blank. The app isn't changed to suit renders.
public struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var search = ""

    public init(model: SettingsModel) {
        self.model = model
    }

    /// The window's size; it doesn't resize.
    public static let size = CGSize(width: 860, height: 640)

    public var body: some View {
        NavigationSplitView {
            List(selection: paneBinding) {
                ForEach(panes) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        PaneIcon(pane: pane, size: 20)
                    }
                    .tag(pane)
                    .accessibilityIdentifier("pane-\(pane.rawValue)")
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
            .searchable(text: $search, placement: .sidebar)
        } detail: {
            // The sidebar toggle stays: it is the window's only toolbar item, and without a toolbar
            // macOS gives the window a plain title bar (a centred title over a hard line) instead
            // of the toolbar with the pane's title and content scrolling under it.
            pane.navigationTitle(model.pane.title)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .sheet(item: draftBinding) { _ in RuleSheet(model: model) }
    }

    @ViewBuilder
    private var pane: some View {
        switch model.pane {
        case .general: GeneralPane(model: model)
        case .routing: RoutingPane(model: model)
        case .recent: RecentLinksPane(model: model)
        case .quickSwitch: QuickSwitchPane(model: model)
        }
    }

    /// The panes the sidebar search matches, by title or description.
    private var panes: [Pane] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Pane.allCases }
        return Pane.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
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

/// Problems that need the person, as the first section of every pane: a link that didn't open,
/// a file that can't be read or saved.
struct NoticesSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if model.failure != nil || model.editor.loadError != nil || model.editor.saveError != nil {
            Section {
                if let failure = model.failure {
                    Banner(
                        symbol: "link", title: "The link couldn’t be opened",
                        message:
                            "\(failure.reason) Fix the issue here, or copy the link to open it yourself.",
                        detail: failure.url
                    ) {
                        Button("Copy Link") { model.copyFailedLink() }
                        Button("Dismiss") { model.failure = nil }
                    }
                }
                if let error = model.editor.loadError {
                    Banner(symbol: "doc.badge.ellipsis", title: "Settings couldn’t be read", message: error) {
                        Button("Reload") { model.edit { $0.reload() } }
                        Button("Show in Finder") { model.revealConfigFile() }
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
                    Banner(
                        symbol: "exclamationmark.triangle", title: "Changes couldn’t be saved", message: error
                    ) {
                        Button("Retry") { model.flush() }
                    }
                }
            }
        }
    }
}

/// A notice as a form row, with its recovery actions.
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
