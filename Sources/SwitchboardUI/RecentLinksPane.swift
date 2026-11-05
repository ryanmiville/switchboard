import Foundation
import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The links Switchboard opened, newest first: each link, where it opened and why, with a menu to
/// make a rule for it (as System Settings puts a ⋯ menu on each known Wi-Fi network).
struct RecentLinksPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let e = model.editor
        Form {
            NoticesSection(model: model)

            if !e.config.historyEnabled {
                Section {
                    LabeledContent {
                        Button("Turn On") { model.edit { $0.setHistoryEnabled(true) } }
                    } label: {
                        RowLabel(
                            title: "History is off",
                            caption: "Links that open from now on aren’t listed here.")
                    }
                    .accessibilityIdentifier("recent-history-off")
                }
            }

            Section {
                if let error = e.recentError {
                    ErrorText(error)
                } else if e.recent.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No Recent Links").font(.headline)
                        Text("Links you open from other apps show up here, with the rule that sent them.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .accessibilityIdentifier("recent-empty")
                } else {
                    ForEach(e.recent, id: \.id) { entry in
                        RecentLinkRow(entry: entry, editor: e, now: model.now) {
                            linkActions(entry)
                        }
                        .contextMenu { linkActions(entry) }
                    }
                }
            } header: {
                Text("Recent links")
            } footer: {
                Footer(
                    "Each link shows the rule that matched when it opened; rules may have changed since. The newest \(History.keep) are kept."
                )
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func linkActions(_ entry: History.Entry) -> some View {
        Button("Add Rule for This Link…") { model.addRule(for: entry) }
        Button("Copy Link") { model.copyLink(entry.url) }
    }
}

/// One link: where it went on the left, as the address and the reason; the profile, browser and
/// time on the right, then its menu.
struct RecentLinkRow<Actions: View>: View {
    let entry: History.Entry
    let editor: Editor
    let now: Timestamp
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // Without the query, fragment and user info, which can carry tokens; Copy Link
                // copies the whole link.
                Text(entry.redactedURL).lineLimit(1).truncationMode(.middle)
                if entry.result == .failed {
                    Label(entry.error ?? "The link couldn’t be opened.", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text(entry.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(
                        entry.profileName
                            ?? editor.profileName(browser: entry.browser, profile: entry.profile)
                    )
                    .lineLimit(1)
                    Text("\(editor.browserName(entry.browser)) · \(ago)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                BrowserIcon(locator: entry.browser, size: 26)
            }
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add a rule for this link, or copy it")
            .accessibilityIdentifier("recent-actions")
        }
        .accessibilityElement(children: .contain)
    }

    /// "2 min. ago", from the time the window last read the clock.
    private var ago: String {
        guard let time = entry.timestamp else { return entry.time }
        if now.seconds - time.seconds < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(time.seconds)),
            relativeTo: Date(timeIntervalSince1970: TimeInterval(now.seconds)))
    }
}
