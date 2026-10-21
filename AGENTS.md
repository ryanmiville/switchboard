# Switchboard

Personal macOS URL router built with SwiftUI/AppKit. Keep changes small and use the standard library and Apple frameworks unless a dependency has a clear payoff.

## Commands

Requires full Xcode 26.4 (including its command-line tools), Swift 6, and macOS. The app targets macOS 13+.

- `make test` — fast, unhosted Swift Testing tests against the same source files the app compiles.
- `make verify` — formatting, tests, Debug/Release builds, bundle checks, and whitespace checks. This is the completion check for code/build changes and runs in CI.
- `make format` — apply the checked-in Swift formatting rules.
- `make debug` / `make release` — build into `.build/xcode`.
- `make debug-install` / `make install` — build, copy to `/Applications`, and register the app. Run only when installation is requested.

Tests use temporary files and fake browsers; they have no personal configuration or real browser access. Run them, fix relevant failures, and rerun without asking for permission at each step. Use `make verify` before handing off code changes, and report any checks you could not run. CI uses the Xcode 26.4 family on `macos-26`.

## Where to look

| Area | Source |
| --- | --- |
| URL events, launch mode, shutdown and recovery UI | `Switchboard/SwitchboardApp.swift` |
| Routing lifetime decisions | `Switchboard/RoutingSession.swift` |
| JSON configuration and atomic persistence | `Switchboard/Config.swift` |
| Editor state, autosave and flush | `Switchboard/ConfigViewModel.swift` |
| Rule matching and preview decisions | `Switchboard/Router.swift` |
| Browser-specific profile paths and legacy names | `Switchboard/BrowserProfiles.swift` |
| Installed browsers and executable launching | `Switchboard/BrowserDiscovery.swift`, `Switchboard/BrowserLauncher.swift` |
| Editor and URL preview | `Switchboard/ContentView.swift` |
| Regression tests | `Tests/SwitchboardCoreTests/` |

The Swift package excludes the app entry point and editor view so tests do not launch NSApplication. New app sources must also be added to the Xcode project's Sources phase. Services are structs; observable UI state and AppKit delegates are classes with main-actor isolation where appropriate.

## Behavior to preserve

- First matching rule wins. Contains and Exact match the complete URL case-insensitively. Domain matches the host or a subdomain at a dot boundary. Empty patterns are ignored. Unmatched URLs use the configured default profile.
- Configuration lives at `~/.config/switchboard/config.json`. Keep existing JSON readable. A missing file may use defaults; malformed or unreadable files must not be silently replaced. Saves use atomic replacement, and failures retain edits for retry.
- Persist Chromium directory identifiers (`Default`, `Profile 1`, etc.), and show display names only in the UI. Accept legacy display names only when unambiguous. Directory identifiers take precedence over colliding display names. Browser data locations are browser-specific.
- Launch the browser executable directly using `Bundle.executableURL` and a Process argument array. Do not use `open -a --args`; profiles must work when the browser is already running. Pass only complete HTTP/HTTPS URLs and preserve the original URL when launching.
- Surface failures with a recovery action. Do not guess a different browser/profile or fall back through the system default browser, which may be Switchboard itself.
- Routing must preserve an existing editor session. Flush pending edits before routing from the editor or quitting it. A temporary routing launch exits only after the latest URL's idle delay.
- Keep App Sandbox disabled: launching the browser requires subprocess control. Preserve HTTP/HTTPS and HTML declarations in `Info.plist` so macOS recognizes the app as a browser.

## Verification and review

For behavior fixes, add a regression test that reaches the failing behavior. Use isolated fixture configuration and Local State files, and inject the process runner instead of opening real browsers. Do not weaken tests to make a change pass.

Review changes for configuration compatibility, wrong-profile launches, swallowed failures, and unintended writes to personal files. Keep installation separate from normal verification. Mention whether actual browser delivery or GUI behavior was exercised; a successful process launch alone does not prove the right browser window opened.
