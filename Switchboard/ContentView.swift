import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ConfigViewModel
    var onOpen: (@escaping () -> Void) -> Void
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focusedField: UUID?
    @State private var testURL = ""

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.loadError {
                errorMessage(error) {
                    Button("Open Configuration File") { NSWorkspace.shared.open(viewModel.configURL) }
                    Button("Retry Loading") { viewModel.reload() }
                }
            }
            if let error = viewModel.saveError {
                errorMessage(error) { Button("Retry Saving") { viewModel.flush() } }
            }
            if let error = viewModel.profileError {
                errorMessage(error) { Button("Refresh Profiles") { viewModel.refreshProfiles() } }
            }
            editor
                .disabled(viewModel.loadError != nil)
        }
        .frame(minWidth: 560, minHeight: 440)
        .onAppear { onOpen { openWindow(id: "settings") } }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.config.routes) { route in
                        RouteRow(
                            route: viewModel.binding(for: route),
                            viewModel: viewModel,
                            focusedField: $focusedField
                        )
                    }
                }
                .padding()
            }
            HStack {
                Text("First matching rule wins.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("New Route") { viewModel.addRoute() }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                profilePicker("Default", selection: $viewModel.config.defaultProfile)
                Picker("Browser", selection: $viewModel.config.browser) {
                    if !viewModel.availableBrowsers.contains(where: { $0.path == viewModel.config.browser }) {
                        Text("Unavailable: \((viewModel.config.browser as NSString).lastPathComponent)")
                            .tag(viewModel.config.browser)
                    }
                    ForEach(viewModel.availableBrowsers) { browser in
                        Text(browser.name).tag(browser.path)
                    }
                }
                TextField("Test an HTTP or HTTPS URL", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                if !testURL.isEmpty {
                    Text(preview).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private var preview: String {
        guard let url = URL(string: testURL), Router.isWebURL(url) else {
            return "Enter a complete URL, such as https://example.com."
        }
        let decision = Router(config: viewModel.config).decision(url: url)
        let name =
            viewModel.availableProfiles.first { $0.directory == decision.profile }?.name ?? decision.profile
        if let route = decision.route,
            let index = viewModel.config.routes.firstIndex(where: { $0.id == route.id })
        {
            return "Rule \(index + 1) → \(name) (\(decision.profile))"
        }
        return "Default → \(name) (\(decision.profile))"
    }

    private func profilePicker(_ label: String, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            if !viewModel.availableProfiles.contains(where: { $0.directory == selection.wrappedValue }) {
                Text("Unavailable: \(selection.wrappedValue)").tag(selection.wrappedValue)
            }
            ForEach(viewModel.availableProfiles) { profile in
                Text("\(profile.name) (\(profile.directory))").tag(profile.directory)
            }
        }
    }

    private func errorMessage<Actions: View>(_ message: String, @ViewBuilder actions: () -> Actions)
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .textSelection(.enabled)
            HStack { actions() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.yellow.opacity(0.12))
    }
}

private struct RouteRow: View {
    @Binding var route: Route
    @ObservedObject var viewModel: ConfigViewModel
    var focusedField: FocusState<UUID?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Match", selection: $route.condition) {
                    ForEach(Condition.allCases, id: \.self) { condition in
                        Text(condition.label).tag(condition)
                    }
                }
                .frame(width: 170)
                TextField(route.condition == .domain ? "example.com" : "URL pattern", text: $route.value)
                    .textFieldStyle(.roundedBorder)
                    .focused(focusedField, equals: route.id)
                    .help("Empty patterns are ignored. Domain matches include subdomains.")
                Button {
                    viewModel.moveRoute(route, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(viewModel.config.routes.first?.id == route.id)
                .help("Move rule earlier")
                Button {
                    viewModel.moveRoute(route, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(viewModel.config.routes.last?.id == route.id)
                .help("Move rule later")
                Button {
                    focusedField.wrappedValue = nil
                    viewModel.deleteRoute(route)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .help("Delete rule")
            }
            Picker("Open in", selection: $route.profile) {
                if !viewModel.availableProfiles.contains(where: { $0.directory == route.profile }) {
                    Text("Unavailable: \(route.profile)").tag(route.profile)
                }
                ForEach(viewModel.availableProfiles) { profile in
                    Text("\(profile.name) (\(profile.directory))").tag(profile.directory)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
