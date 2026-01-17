import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Switchboard")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("URL Router for Chromium Profiles")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.vertical)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Setup:")
                    .font(.headline)
                
                Text("1. Edit config at:")
                    .font(.subheadline)
                Text("~/.config/switchboard/config.json")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                
                Text("2. Set as default browser:")
                    .font(.subheadline)
                Text("System Settings → Desktop & Dock → Default web browser")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(30)
        .frame(width: 400, height: 300)
    }
}

#Preview {
    ContentView()
}
