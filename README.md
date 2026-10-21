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

Open Switchboard to choose a default browser and profile, then add rules. Each rule can use the default browser or a different Chromium browser, with its own profile. For example, work links can open a Google Chrome profile while everything else opens Ryan in Helium. Move rules with the arrow buttons: the first match wins. The URL preview shows the selected browser and profile without opening anything.

Changing a rule’s browser clears its profile choice so you can select a profile belonging to the new browser. Profile directory names can be identical across browsers, so they are never treated as a shared identity.

- **Contains** matches a substring anywhere in the complete URL, including its query string.
- **Exact** matches the complete URL.
- **Domain** matches a host and its subdomains. For example, `github.com` matches `docs.github.com`, but not `github.com.example.com` or a query parameter mentioning GitHub.

All matching is case-insensitive. Empty patterns are ignored. Unmatched URLs use the configured default browser and profile.

Settings are saved automatically after a short delay. Pending changes are saved before quitting or routing a link from an open editor. Loading and saving errors appear in the editor with recovery actions. Invalid configuration is left untouched, and failed saves retain changes in the window for retry.

The configuration file is `~/.config/switchboard/config.json`:

```json
{
  "browser": "/Applications/Helium.app",
  "defaultProfile": "Default",
  "routes": [
    {
      "condition": "domain",
      "value": "gitlab.com",
      "browser": "/Applications/Google Chrome.app",
      "profile": "Profile 2"
    }
  ]
}
```

The top-level `browser` and `defaultProfile` define the default destination. A rule’s optional `browser` overrides the default browser. Older rules without it keep using the top-level browser, so existing files continue to work.

Profiles are saved as Chromium directory identifiers, while the editor displays friendly names alongside them. Profiles are discovered and validated within each destination’s browser. Older files containing display names are resolved when unambiguous and converted to directory identifiers when saved. Missing or ambiguous selections require choosing a profile in the editor.

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
