# SWITCHBOARD

macOS URL router. Sets as default browser, routes URLs to specific Chromium browser profiles based on pattern matching.

## STRUCTURE

```
Switchboard/
├── Switchboard.xcodeproj/
└── Switchboard/
    ├── SwitchboardApp.swift   # App entry + URL event handling
    ├── Config.swift           # JSON config loader (~/.config/switchboard/config.json)
    ├── Router.swift           # URL → profile matching (substring contains)
    ├── BrowserLauncher.swift  # Launches browser executable with --profile-directory
    ├── ContentView.swift      # Minimal setup instructions UI
    └── Info.plist             # URL scheme registration (http/https)
```

## WHERE TO LOOK

| Task | File |
|------|------|
| URL handling | `SwitchboardApp.swift` - `handleGetURL`, `routeURL` |
| Add matching logic | `Router.swift` - currently substring match only |
| Change browser launch | `BrowserLauncher.swift` - builds executable path from .app bundle |
| Config format | `Config.swift` - Codable structs for JSON |

## ARCHITECTURE

- **Accessory app**: No dock icon, no menu bar (`NSApp.setActivationPolicy(.accessory)`)
- **Fire and forget**: Routes URL then terminates after 0.5s
- **Hybrid SwiftUI/AppKit**: Uses `@NSApplicationDelegateAdaptor` for `NSAppleEventManager` URL events
- **Direct process launch**: Calls browser executable directly (not `open -a`) to pass args when browser already running

## CONVENTIONS

- Immutable value types: `struct` for services, `class` only for AppDelegate (required)
- Guard-based validation with early returns
- Error handling: try/catch with silent fallback to default browser

## ANTI-PATTERNS

- **Don't use `open -a --args`**: Args ignored when app already running. Must call executable directly.
- **Don't enable sandbox**: Requires subprocess control for browser launching

## CONFIG

Location: `~/.config/switchboard/config.json`

```json
{
  "browser": "/Applications/Helium.app",
  "defaultProfile": "Default",
  "routes": [
    { "contains": "github.com", "profile": "Profile 1" }
  ]
}
```

Profile names = Chromium directory names (`Default`, `Profile 1`, `Profile 2`, etc.)

## BUILD

```bash
cd Switchboard
xcodebuild -project Switchboard.xcodeproj -scheme Switchboard -configuration Debug build
cp -R ~/Library/Developer/Xcode/DerivedData/Switchboard-*/Build/Products/Debug/Switchboard.app /Applications/
```

## NOTES

- Must register with Launch Services: `lsregister -f /Applications/Switchboard.app`
- Set as default: System Settings → Desktop & Dock → Default web browser
- Info.plist requires `CFBundleDocumentTypes` + `LSHandlerRank` to appear in browser list
