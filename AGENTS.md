# Switchboard

Personal macOS URL router built with SwiftUI/AppKit. Keep changes small and use the standard library and Apple frameworks unless a dependency has a clear payoff.

## Commands

Requires full Xcode 26.4 (including its command-line tools), Swift 6, and macOS. The app targets macOS 13+.

- `make test` — fast, unhosted Swift Testing tests against the same source files the app compiles.
- `make verify` — formatting, tests, Debug/Release builds, bundle checks, and whitespace checks. This is the completion check for code/build changes and runs in CI.
- `make format` — apply the checked-in Swift formatting rules.
- `make verify-linux` — on Linux (cloud sessions): formatting, the Foundation-only tests, and whitespace checks. Use it while developing the core and CLI there. It does not replace `make verify`; report `make verify` as not run.
- `make debug` / `make release` — build into `.build/xcode`.
- `make debug-install` / `make install` — build, copy to `/Applications`, and register the app. Run only when installation is requested.
- `make install-cli` — link `~/.local/bin/switchboard` to the tool inside the installed app. Run only when installation is requested.

Tests use temporary files and fake browsers; they have no personal configuration or real browser access. Run them, fix relevant failures, and rerun without asking for permission at each step. Use `make verify` before handing off code changes, and report any checks you could not run. CI uses the Xcode 26.4 family on `macos-26`.

## Where to look

| Area | Source |
| --- | --- |
| URL events, launch mode, shutdown and recovery UI | `Switchboard/SwitchboardApp.swift` |
| Routing lifetime decisions | `Switchboard/RoutingSession.swift` |
| JSON configuration and atomic persistence | `Switchboard/Config.swift` |
| Compare-and-swap saves, revisions, and file locks | `Switchboard/ConfigStore.swift` |
| Link history: storage, redaction, recording | `Switchboard/History.swift` |
| CLI rule edits: resolution, shadowing, verification | `Switchboard/RuleOperations.swift` |
| CLI commands, output, doctor, and agent skill | `Switchboard/CLI/`, entry point `CLI/main.swift` |
| Editor state, autosave and flush | `Switchboard/ConfigViewModel.swift` |
| Rule matching and preview decisions | `Switchboard/Router.swift` |
| Browser-specific profile paths and legacy names | `Switchboard/BrowserProfiles.swift` |
| Installed browsers and executable launching | `Switchboard/BrowserDiscovery.swift`, `Switchboard/BrowserLauncher.swift` |
| Editor and URL preview | `Switchboard/ContentView.swift` |
| Regression tests | `Tests/SwitchboardCoreTests/` |

The Swift package excludes the app entry point and editor view. The CLI's command definitions in `Switchboard/CLI` compile into `SwitchboardCore` in the package; Xcode's `SwitchboardCLI` target compiles them as one module with only the Foundation-only core files they need, and the app embeds the result in `Contents/Helpers`. Add a core file the CLI uses to both Sources phases. Reopen tests call the real app delegate with isolated configuration and temporary AppKit windows; they do not launch the app or browsers. New app sources must also be added to the Xcode project's Sources phase. Files that import AppKit, SwiftUI, Carbon, Combine, or ServiceManagement must be listed in `Package.swift`'s Linux exclusions, along with tests that need them; keep configuration types Foundation-only so the CLI can share them. Services are structs; observable UI state and AppKit delegates are classes with main-actor isolation where appropriate.

## Behavior to preserve

- First matching rule wins. Contains and Exact match the complete URL case-insensitively. Domain matches the host or a subdomain at a dot boundary. Empty patterns are ignored. Routing returns a browser/profile pair; unmatched URLs use the configured default browser and profile. A rule can override its browser; omitted browser fields inherit the top-level browser for compatibility with existing JSON.
- Configuration lives at `~/.config/switchboard/config.json`. Keep existing JSON readable. A missing file may use defaults; malformed or unreadable files must not be silently replaced. Saves use atomic replacement, and failures retain edits for retry.
- Persist Chromium directory identifiers (`Default`, `Profile 1`, etc.), and show display names only in the UI. Discover and validate each profile within its destination’s browser; identical directory IDs in Chrome and Helium can refer to different people. Changing a rule’s browser requires a new profile selection. Accept legacy display names only when unambiguous. Directory identifiers take precedence over colliding display names. Browser data locations are browser-specific.
- Launch the browser executable directly using `Bundle.executableURL` and a Process argument array. Do not use `open -a --args`; profiles must work when the browser is already running. Pass only complete HTTP/HTTPS URLs and preserve the original URL when launching.
- Surface failures with a recovery action. Do not guess a different browser/profile or fall back through the system default browser, which may be Switchboard itself.
- Routing must preserve an existing editor session. Flush pending edits before routing from the editor or quitting it. A temporary routing launch exits only after the latest URL's idle delay.
- Opening or reopening the app starts its menu bar and shortcut without opening Settings. Settings is a single window opened explicitly from the menu; repeated Settings requests focus or restore it, creating a window only when none is open. Suppress AppKit's default reopening.
- The CLI and the app share `config.json` with no daemon. Every save is a compare-and-swap against the loaded revision under a `flock`; never overwrite a file that changed since it was read. The CLI changes only the rules it was asked to change, refuses ambiguous names (exit 3) instead of guessing, and never opens links.
- History recording is best effort: it never blocks, delays, or fails opening a link. URLs are redacted in CLI output unless `--full-urls` is passed.
- Keep App Sandbox disabled: launching the browser requires subprocess control. Preserve HTTP/HTTPS and HTML declarations in `Info.plist` so macOS recognizes the app as a browser.

## Verification and review

For behavior fixes, add a regression test that reaches the failing behavior. Use isolated fixture configuration and Local State files, and inject the process runner instead of opening real browsers. Cross-browser tests should cover a Chrome rule with a Helium default, browser-specific profile choices, and legacy rules with no browser override. Do not weaken tests to make a change pass.

Review changes for configuration compatibility, wrong-profile launches, swallowed failures, and unintended writes to personal files. Keep installation separate from normal verification. Mention whether actual browser delivery or GUI behavior was exercised; a successful process launch alone does not prove the right browser window opened.

## Git

Commit, merge, and push directly to `main`. Feature branches and pull requests aren't needed, including in cloud sessions that start on another branch: merge that work into `main` and push it.
