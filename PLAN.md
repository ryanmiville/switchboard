# Switchboard - macOS URL Router

## Overview
Native Swift/SwiftUI app that acts as default browser, routing URLs to specific Helium browser profiles based on "contains" pattern matching.

## Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│ macOS URL Event │────▶│ Switchboard  │────▶│ Helium Profile  │
│ (http/https)    │     │ (match URL)  │     │ --profile-dir=X │
└─────────────────┘     └──────────────┘     └─────────────────┘
                              │
                              ▼
                        ┌──────────────┐
                        │ config.json  │
                        └──────────────┘
```

## Config Format
Location: `~/.config/switchboard/config.json`

```json
{
  "browser": "/Applications/Helium.app",
  "profilePath": "~/Library/Application Support/net.imput.helium",
  "defaultProfile": "Default",
  "routes": [
    { "contains": "console.aws", "profile": "Work" },
    { "contains": "atlassian.net", "profile": "Work" },
    { "contains": "gitlab.com/mycompany", "profile": "Work" },
    { "contains": "youtube.com", "profile": "Personal" }
  ]
}
```

## Implementation

### 1. Xcode Project Setup
- Create new macOS App (SwiftUI lifecycle)
- Bundle ID: `com.switchboard.app`
- Minimum deployment: macOS 13+

### 2. Info.plist - Register as Browser
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>Web URL</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>http</string>
      <string>https</string>
    </array>
  </dict>
</array>
```

### 3. Core Files

| File | Purpose |
|------|---------|
| `SwitchboardApp.swift` | App entry, handle URL open events via `.onOpenURL` |
| `Config.swift` | Codable structs for config.json |
| `Router.swift` | URL matching logic, find first matching route |
| `BrowserLauncher.swift` | Execute `open -a Browser --args --profile-directory=X url` |

### 4. URL Handling Flow
```swift
@main
struct SwitchboardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .handlesExternalEvents(matching: ["http", "https"])
    }
    
    init() {
        // Register URL handler
    }
}
```

On URL received:
1. Load config from `~/.config/switchboard/config.json`
2. Iterate routes, find first where `url.contains(route.contains)`
3. If match: launch browser with that profile
4. Else: launch browser with `defaultProfile`

### 5. Browser Launch Command
```swift
// Using Process to launch with profile
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
process.arguments = [
    "-a", config.browser,
    "--args",
    "--profile-directory=\(profile)",
    url.absoluteString
]
try process.run()
```

## File Structure
```
Switchboard/
├── Switchboard.xcodeproj
├── Switchboard/
│   ├── SwitchboardApp.swift
│   ├── ContentView.swift      # Minimal UI - just shows "Set as default browser" instructions
│   ├── Config.swift
│   ├── Router.swift
│   ├── BrowserLauncher.swift
│   └── Info.plist
```

## Verification
1. Build and run app
2. Create test config at `~/.config/switchboard/config.json`
3. Set Switchboard as default browser (System Settings > Desktop & Dock > Default web browser)
4. Click a link in another app (e.g., Terminal: `open https://youtube.com`)
5. Verify correct Helium profile opens

## Notes
- Profile directories use standard Chromium naming: `Default`, `Profile 1`, `Profile 2`, etc.
- Config file uses these exact directory names (not display names)
