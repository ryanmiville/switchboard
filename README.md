<p align="center">
  <img src="icon_1024x1024.png" width="128" height="128" alt="Switchboard icon">
</p>

# Switchboard

A personal macOS URL router that opens external links in Chromium browser profiles based on rules you define.

## Requirements and installation

- macOS 13 or newer.
- Full Xcode 26.4 with command-line tools selected. Standalone Command Line Tools are insufficient for the app build.
- A supported Chromium browser. Helium has been used with the real app; automated fixtures cover profile discovery for Chrome and its channels, Chromium, Brave, Edge, Vivaldi, and Helium.

Run `make install` to build Release, copy it to `/Applications/Switchboard.app`, and register it with Launch Services. Use `make debug-install` for Debug. Then select Switchboard under **System Settings → Desktop & Dock → Default web browser**.

Installation does not change your default-browser selection automatically.

## Configuration

Open Switchboard to choose a browser, select the default profile, and add rules. Move rules with the arrow buttons: the first match wins. The URL preview shows which rule and profile would be used without opening anything.

- **Contains** matches a substring anywhere in the complete URL, including its query string.
- **Exact** matches the complete URL.
- **Domain** matches a host and its subdomains. For example, `github.com` matches `docs.github.com`, but not `github.com.example.com` or a query parameter mentioning GitHub.

All matching is case-insensitive. Empty patterns are ignored. Unmatched URLs use the configured default profile.

Settings are saved automatically after a short delay. Pending changes are saved before quitting or routing a link from an open editor. Loading and saving errors appear in the editor with recovery actions. Invalid configuration is left untouched, and failed saves retain changes in the window for retry.

The configuration file is `~/.config/switchboard/config.json`:

```json
{
  "browser": "/Applications/Helium.app",
  "defaultProfile": "Default",
  "routes": [
    { "condition": "domain", "value": "github.com", "profile": "Profile 1" }
  ]
}
```

Profiles are saved as Chromium directory identifiers, while the editor displays friendly names alongside them. Older files containing display names are resolved when unambiguous and converted to directory identifiers when saved. Missing or ambiguous selections require choosing a profile in the editor.

A link launches the selected browser executable directly so profile arguments work even when the browser is already running. A temporary routing launch exits shortly afterward. An existing editor stays open. If a link cannot be launched, Switchboard offers settings or a copy of the link instead of silently choosing another browser.

## Development

```sh
make test     # Fast isolated regression tests; no app or real browser is launched
make verify   # Formatting, tests, Debug/Release builds, bundle and whitespace checks
make format   # Apply Swift formatting
make debug    # Build Debug into .build/xcode
make release  # Build Release into .build/xcode
```

Tests use Swift Testing through `Package.swift`, compiling the same production source files without the app entry point or editor view. Use `make test` rather than `xcodebuild test`. There are no third-party package dependencies. Swift 6 concurrency checks and Swift warnings-as-errors are enabled for the app.

Normal verification does not install the app or modify your configuration. Xcode automatically registers build products; the build commands unregister their local products afterward. Explicit installation registers the copy in `/Applications`.

GitHub Actions runs `make verify` for pull requests and pushes to `main`, using the Xcode 26.4 family on `macos-26`. Failure logs are uploaded as artifacts. The workflow starts running once it is pushed to GitHub.

For changes to URL handling or launching, also smoke-check the app on macOS: open links with the browser closed and already running, confirm the selected profile, open several links quickly, and verify an open editor stays open. Automated fixtures cannot establish actual browser-window delivery or compatibility with every supported macOS release.
