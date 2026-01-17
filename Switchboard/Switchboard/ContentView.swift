import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ConfigViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Switchboard")
                    .font(.headline)
                Spacer()
                Button("New Route") {
                    viewModel.addRoute()
                }
            }
            .padding()
            
            Divider()
            
            // Routes list
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach($viewModel.config.routes) { $route in
                        RouteRow(
                            route: $route,
                            profiles: viewModel.availableProfiles,
                            onDelete: { viewModel.deleteRoute(route) }
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer - default profile & browser
            VStack(spacing: 12) {
                HStack {
                    Text("Default")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $viewModel.config.defaultProfile) {
                        ForEach(viewModel.availableProfiles, id: \.self) { profile in
                            Text(profile).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                
                HStack {
                    Text("Browser")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("Browser path", text: $viewModel.config.browser)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 400)
    }
}

struct RouteRow: View {
    @Binding var route: Route
    let profiles: [String]
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // URL condition row
            HStack {
                Label("URL", systemImage: "link")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                
                Picker("", selection: $route.condition) {
                    ForEach(Condition.allCases, id: \.self) { condition in
                        Text(condition.label).tag(condition)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                
                TextField("pattern", text: $route.value)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Profile row
            HStack {
                Label("Open in", systemImage: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                
                Picker("", selection: $route.profile) {
                    ForEach(profiles, id: \.self) { profile in
                        Text(profile).tag(profile)
                    }
                }
                .labelsHidden()
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ContentView()
}
